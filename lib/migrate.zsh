#!/usr/bin/env zsh
#
# Database migration command for SpendCloud plugin.


# ═══════════════════════════════════════════════════════════════════════════════
# MIGRATE COMMAND
# ═══════════════════════════════════════════════════════════════════════════════

#######################################
# Check if cluster is running.
# Globals:
#   SC_API_CONTAINER_PATTERN
# Returns:
#   0 if running, 1 otherwise
#######################################
_migrate_is_cluster_running() {
  emulate -L zsh ${=${options[xtrace]:#off}:+-o xtrace}
  setopt extended_glob warn_create_global typeset_silent no_short_loops rc_quotes no_auto_pushd
  local MATCH REPLY; integer MBEGIN MEND; local -a match mbegin mend reply

  local container
  container="$(_sc_find_container "${SC_API_CONTAINER_PATTERN}")"
  [[ -n "${container}" ]]
}

#######################################
# Get running API container name.
# Globals:
#   SC_API_CONTAINER_PATTERN
# Outputs:
#   Container name to stdout
#   Error message to stderr if not found
# Returns:
#   0 if found, 1 otherwise
#######################################
_migrate_get_container() {
  emulate -L zsh ${=${options[xtrace]:#off}:+-o xtrace}
  setopt extended_glob warn_create_global typeset_silent no_short_loops rc_quotes no_auto_pushd
  local MATCH REPLY; integer MBEGIN MEND; local -a match mbegin mend reply

  _sc_find_container "${SC_API_CONTAINER_PATTERN}" || {
    echo "API container not found. Start with 'cluster'." >&2
    return 1
  }
}

#######################################
# Get migration group order.
# Globals:
#   MIGRATION_GROUP_ORDER (optional override)
# Outputs:
#   Space-separated group names to stdout
# Returns:
#   0 always
#######################################
_migrate_get_groups() {
  emulate -L zsh ${=${options[xtrace]:#off}:+-o xtrace}
  setopt extended_glob warn_create_global typeset_silent no_short_loops rc_quotes no_auto_pushd
  local MATCH REPLY; integer MBEGIN MEND; local -a match mbegin mend reply

  local -a groups=(proactive_config proactive-default sharedStorage customers)
  if [[ -n "${MIGRATION_GROUP_ORDER:-}" ]]; then
    local cleaned="${MIGRATION_GROUP_ORDER// /}"
    IFS=',' read -r -A groups <<<"${cleaned}"
  fi
  echo "${groups[@]}"
}

#######################################
# Execute artisan command in API container.
# Arguments:
#   1 - Container name
#   2+ - Artisan command and arguments
# Outputs:
#   Command output to stdout/stderr
# Returns:
#   Exit code from artisan command
#######################################
_migrate_exec() {
  local container="${1}"
  shift
  docker exec -it "${container}" php artisan "$@"
}

#######################################
# Run grouped migrations in default order.
# Arguments:
#   1 - Container name
# Outputs:
#   Migration status to stdout
# Returns:
#   Exit code from migrate-all command
#######################################
_migrate_all() {
  emulate -L zsh ${=${options[xtrace]:#off}:+-o xtrace}
  setopt extended_glob warn_create_global typeset_silent no_short_loops rc_quotes no_auto_pushd
  local MATCH REPLY; integer MBEGIN MEND; local -a match mbegin mend reply

  local container="${1}"
  local -a groups
  IFS=' ' read -r -A groups <<<"$(_migrate_get_groups)"
  echo "Running grouped migrations in order: ${groups[*]}"
  _migrate_exec "${container}" migrate-all --groups="$(
    IFS=,
    echo "${groups[*]}"
  )"
}

#######################################
# Analyze missing table errors and suggest fixes.
# Arguments:
#   1 - Container name
#   2 - Group name
#   3 - Error output
# Outputs:
#   Diagnostic info and suggestions
#######################################
_migrate_diagnose_missing_table() {
  local container="${1}" group="${2}" output="${3}"

  # Extract table name from error
  local table
  table=$(echo "${output}" | grep -oP "Table '.*?\K[^.']+(?=' doesn't exist)" | head -1)

  if [[ -z "${table}" ]]; then
    return 1
  fi

  _sc_info "🔍 Analyzing missing table: ${table}"

  # Check if this is a customer-specific database issue
  local database
  database=$(echo "${output}" | grep -oP "Table '\K[^.']+(?=\.)" | head -1)

  if [[ -n "${database}" ]]; then
    echo ""
    _sc_info "📊 Issue details:"
    echo "  • Database: ${database}"
    echo "  • Missing table: ${table}"
    echo ""

    # Check if table exists in migrations but not in DB
    _sc_info "Checking migration history for this table..."
    local migration_check
    migration_check=$(_migrate_exec "${container}" db:table "${database}" "${table}" 2>&1 || echo "not found")

    if echo "${migration_check}" | grep -q "not found\|doesn't exist"; then
      echo ""
      _sc_warn "💡 Recommended actions (in order of preference):"
      echo ""
      echo "  1. Skip this migration (safest for production):"
      echo "     → Already handled automatically - no action needed"
      echo ""
      echo "  2. Find and run the missing table creation migration:"
      echo "     → migrate check ${database}"
      echo "     → Look for migrations that create '${table}' table"
      echo ""
      echo "  3. Rebuild the entire customer database (DESTRUCTIVE):"
      echo "     → This will delete all data for ${database}!"
      echo "     → Only if this is a test/dev database"
      echo ""
    fi
  fi
}

#######################################
# Run each migration group separately to debug failures.
# Arguments:
#   1 - Container name
# Outputs:
#   Migration status for each group
# Returns:
#   0 if all succeeded, 1 on first failure
#######################################
_migrate_debug() {
  emulate -L zsh ${=${options[xtrace]:#off}:+-o xtrace}
  setopt extended_glob warn_create_global typeset_silent no_short_loops rc_quotes no_auto_pushd
  local MATCH REPLY; integer MBEGIN MEND; local -a match mbegin mend reply

  local container="${1}"
  local -a groups
  IFS=' ' read -r -A groups <<<"$(_migrate_get_groups)"
  echo "Running each group separately (stops on first failure)"

  local group
  for group in "${groups[@]}"; do
    echo "=== Group: ${group} ==="
    _migrate_exec "${container}" migrate-all --groups="${group}" || {
      echo "Group '${group}' FAILED. Aborting debug run." >&2
      return 1
    }
  done
}

#######################################
# Run migrations with smart error handling.
# Runs groups sequentially, continues on error, reports all failures.
# Arguments:
#   1 - Container name
# Outputs:
#   Migration status to stdout
# Returns:
#   0 always (warnings don't fail)
#######################################
_migrate_safe() {
  emulate -L zsh ${=${options[xtrace]:#off}:+-o xtrace}
  setopt extended_glob warn_create_global typeset_silent no_short_loops rc_quotes no_auto_pushd
  local MATCH REPLY; integer MBEGIN MEND; local -a match mbegin mend reply

  local container="${1}"
  local -a groups warned_groups
  IFS=' ' read -r -A groups <<<"$(_migrate_get_groups)"

  _sc_info "Running migrations in safe mode (continues on errors)..."
  echo "Migration order: ${groups[*]}"
  echo ""

  local group exit_code output
  for group in "${groups[@]}"; do
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    _sc_info "Group: ${group}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    output=$(_migrate_exec "${container}" migrate-all --groups="${group}" 2>&1)
    exit_code=$?
    echo "${output}"

    if ((exit_code != 0)); then
      # Check if error is due to missing table (known issue, not critical)
      if echo "${output}" | grep -q "Base table or view not found"; then
        _sc_warn "⚠️  Group '${group}' has dependency issues (missing tables)"

        # Provide detailed diagnosis
        _migrate_diagnose_missing_table "${container}" "${group}" "${output}"

        _sc_info "Continuing with remaining migrations..."
        warned_groups+=("${group}")
        echo ""
      else
        _sc_warn "⚠️  Group '${group}' had errors but continuing..."
        warned_groups+=("${group}")
        echo ""
      fi
    else
      _sc_success "✓ Group '${group}' completed successfully"
      echo ""
    fi
  done

  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  if ((${#warned_groups[@]} > 0)); then
    _sc_warn "Migration completed with ${#warned_groups[@]} warning(s)"
    echo "Groups with warnings: ${warned_groups[*]}"
    _sc_info "These warnings are usually safe to ignore for existing databases"
    return 0
  else
    _sc_success "All migration groups completed successfully!"
    return 0
  fi
}

#######################################
# Run fresh migrations for a specific group (drop & recreate).
# Arguments:
#   1 - Container name
#   2 - Group name
# Outputs:
#   Migration status to stdout
# Returns:
#   Exit code from fresh command
#######################################
_migrate_fresh() {
  local container="${1}" group="${2}"
  [[ -z "${group}" ]] && {
    echo "Usage: migrate fresh <group_name>" >&2
    echo "Available groups: $(_migrate_get_groups)" >&2
    return 1
  }
  _sc_warn "Running FRESH migrations for group: ${group}"
  _sc_warn "This will DROP existing tables for this group!"
  _migrate_exec "${container}" migrate:fresh --groups="${group}"
}

#######################################
# Check specific database for missing migrations.
# Arguments:
#   1 - Container name
#   2 - Database name (e.g., sherpa, spend-cloud)
# Outputs:
#   List of pending migrations
# Returns:
#   Exit code from status command
#######################################
_migrate_check_db() {
  local container="${1}" database="${2}"
  [[ -z "${database}" ]] && {
    echo "Usage: migrate check <database_name>" >&2
    echo "Example: migrate check sherpa" >&2
    return 1
  }
  _sc_info "Checking migration status for database: ${database}"
  _migrate_exec "${container}" migrate:status --database="${database}"
}

#######################################
# Retry failed group with force flag (skips confirmation prompts).
# Arguments:
#   1 - Container name
#   2 - Group name
# Outputs:
#   Migration status to stdout
# Returns:
#   Exit code from migrate command
#######################################
_migrate_retry() {
  local container="${1}" group="${2}"
  [[ -z "${group}" ]] && {
    echo "Usage: migrate retry <group_name>" >&2
    echo "Available groups: $(_migrate_get_groups)" >&2
    return 1
  }
  _sc_info "Retrying migrations for group: ${group} (with --force)"
  _migrate_exec "${container}" migrate-all --groups="${group}" --force
}

#######################################
# Attempt to heal database by running all pending migrations.
# Tries to create missing tables by running earlier migrations.
# Arguments:
#   1 - Container name
# Outputs:
#   Healing progress
# Returns:
#   0 if healing attempted, 1 on error
#######################################
_migrate_heal() {
  emulate -L zsh ${=${options[xtrace]:#off}:+-o xtrace}
  setopt extended_glob warn_create_global typeset_silent no_short_loops rc_quotes no_auto_pushd
  local MATCH REPLY; integer MBEGIN MEND; local -a match mbegin mend reply

  local container="${1}"

  _sc_info "🏥 Attempting to heal database by running pending migrations..."
  echo ""

  # Get list of all pending migrations
  _sc_info "Step 1: Checking migration status..."
  _migrate_exec "${container}" migrate:status

  echo ""
  _sc_info "Step 2: Running all pending migrations (this may take time)..."

  # Run migrate-all for each group which is what actually works
  local -a groups
  IFS=' ' read -r -A groups <<<"$(_migrate_get_groups)"

  local group success=0
  for group in "${groups[@]}"; do
    _sc_info "Healing group: ${group}"
    if _migrate_exec "${container}" migrate-all --groups="${group}" 2>&1 | grep -q "run successfully\|Nothing to migrate"; then
      success=1
    fi
  done

  if ((success)); then
    echo ""
    _sc_success "✓ Healing complete! Run 'migrate' again to verify."
  else
    echo ""
    _sc_info "No pending migrations found. Issue may require manual intervention."
    _sc_warn "Consider: migrate fresh <group> for problematic groups"
  fi
}

#######################################
# Run custom migration groups.
# Arguments:
#   1 - Container name
#   2 - Comma-separated group names
# Outputs:
#   Migration status to stdout
#   Error to stderr if groups empty
# Returns:
#   1 if groups empty, else artisan exit code
#######################################
_migrate_group() {
  local container="${1}" groups="${2}"
  [[ -z "${groups}" ]] && {
    echo "Usage: migrate group <g1,g2,...>" >&2
    return 1
  }
  echo "Running custom groups: ${groups}"
  _migrate_exec "${container}" migrate-all --groups="${groups}"
}

#######################################
# Run migrations for a specific path.
# Arguments:
#   1 - Container name
#   2 - Migration path (customers|config|sharedStorage)
# Outputs:
#   Migration status to stdout
# Returns:
#   Exit code from artisan migrate
#######################################
_migrate_path() {
  local container="${1}" path="${2}"
  _migrate_exec "${container}" migrate --path="database/migrations/${path}"
}

#######################################
# Rollback migrations for a specific path.
# Arguments:
#   1 - Container name
#   2 - Migration path (customers|config|sharedStorage)
# Outputs:
#   Rollback status to stdout
# Returns:
#   Exit code from artisan migrate:rollback
#######################################
_migrate_rollback_path() {
  local container="${1}" path="${2}"
  _migrate_exec "${container}" migrate:rollback --path="database/migrations/${path}"
}

#######################################
# Display migrate command usage.
# Outputs:
#   Help text to stdout
#######################################
_migrate_help() {
  cat <<'EOF'
Usage: migrate [MODE] [OPTIONS]

Modes:
  (default)  Run in safe mode - continues on errors, reports all failures
  all        Run grouped migrate-all (stops on first error)
  debug      Run each group individually in sequence to isolate failures
  safe       Same as default - continues through all groups despite errors

  heal       🏥 Attempt to fix missing table issues automatically
             Runs pending migrations that may create missing tables
             Use this when you see "Base table or view not found" warnings

  fresh      Drop and recreate tables for a specific group
             Usage: migrate fresh <group_name>
             ⚠️  WARNING: This deletes all data for that group!

  retry      Retry a failed group with --force flag
             Usage: migrate retry <group_name>

  check      Check migration status for a specific database
             Usage: migrate check <database_name>
             Example: migrate check sherpa

  group      Run a custom comma-separated list of groups
             Usage: migrate group <g1,g2,...>
  status     Show overall migration status
  tinker     Open artisan tinker within the API container (passes extra args)

Path-specific migrations:
  customers  Run only customers path migrations
  config     Run only config path migrations
  shared     Run only sharedStorage path migrations
  rollback   Roll back a specific path (customers|config|shared)
             Usage: migrate rollback [customers|config|shared]

Environment:
  MIGRATION_GROUP_ORDER="proactive_config,proactive-default,sharedStorage,customers"

🔧 Troubleshooting Missing Tables:

When you see "Base table or view not found" warnings, it usually means:
  1. A migration is trying to ALTER a table that was never CREATE'd
  2. The table creation migration was in a different group or never ran
  3. The database is a legacy/imported one missing some tables

Recommended solutions (in order):
  1. Ignore it - warnings don't block execution (already done automatically)
  2. Try 'migrate heal' - attempts to run pending migrations that create tables
  3. Check specific database: 'migrate check <database_name>'
  4. Fresh rebuild (DESTRUCTIVE): 'migrate fresh <group_name>'

Example workflow:
  $ migrate                    # See warnings about missing tables
  $ migrate heal               # Try to fix by running pending migrations
  $ migrate check sherpa       # Inspect specific database status
  $ migrate fresh customers    # Last resort: rebuild (deletes data!)

Tips:
  - Default mode is safest - continues through errors
  - Warnings about legacy databases are usually safe to ignore
  - Only use 'fresh' on dev/test databases, never production
EOF
}

#######################################
# Manage SpendCloud database migrations.
# Arguments:
#   1 - Action: all|debug|group|status|tinker|customers|config|shared|rollback|help
#   2+ - Additional arguments depending on action
# Globals:
#   MIGRATION_GROUP_ORDER (optional override)
# Outputs:
#   Migration status and results to stdout
# Returns:
#   0 on success, 1 on failure or invalid option
#######################################
migrate() {
  emulate -L zsh ${=${options[xtrace]:#off}:+-o xtrace}
  setopt extended_glob warn_create_global typeset_silent no_short_loops rc_quotes no_auto_pushd
  local MATCH REPLY; integer MBEGIN MEND; local -a match mbegin mend reply

  # Check if cluster is running, start it if not
  if ! _migrate_is_cluster_running; then
    _sc_info "🔍 Cluster not running. Starting cluster..."
    _cluster_start || {
      _sc_error "Failed to start cluster. Cannot run migrations."
      return 1
    }

    # Wait for API container to be ready
    _sc_info "⏳ Waiting for API container to be ready..."
    local retries=0
    local max_retries=30
    while ! _migrate_is_cluster_running && ((retries < max_retries)); do
      sleep 1
      ((retries++))
    done

    if ((retries >= max_retries)); then
      _sc_error "API container did not start in time."
      return 1
    fi

    # Give the container a bit more time to fully initialize
    sleep 3
    _sc_success "API container is ready!"
  fi

  local container
  container="$(_migrate_get_container)" || return 1

  case "${1:-safe}" in
  safe | "") _migrate_safe "${container}" ;;
  all) _migrate_all "${container}" ;;
  debug | each) _migrate_debug "${container}" ;;
  heal) _migrate_heal "${container}" ;;
  fresh) _migrate_fresh "${container}" "${2}" ;;
  retry) _migrate_retry "${container}" "${2}" ;;
  check) _migrate_check_db "${container}" "${2}" ;;
  group) _migrate_group "${container}" "${2}" ;;
  status) _migrate_exec "${container}" migrate:status ;;
  tinker)
    shift
    _migrate_exec "${container}" tinker "$@"
    ;;
  customers) _migrate_path "${container}" "customers" ;;
  config) _migrate_path "${container}" "config" ;;
  shared | sharedstorage) _migrate_path "${container}" "sharedStorage" ;;
  rollback)
    case "${2:-customers}" in
    customers) _migrate_rollback_path "${container}" "customers" ;;
    config) _migrate_rollback_path "${container}" "config" ;;
    shared | sharedstorage) _migrate_rollback_path "${container}" "sharedStorage" ;;
    *)
      echo "Invalid rollback target: ${2}" >&2
      return 1
      ;;
    esac
    ;;
  help | -h | --help) _migrate_help ;;
  *)
    echo "Invalid migrate option: ${1}" >&2
    echo "Run: migrate help" >&2
    return 1
    ;;
  esac
}

# ═══════════════════════════════════════════════════════════════════════════════
# NUKE COMMAND (Dangerous client cleanup tool)
# ═══════════════════════════════════════════════════════════════════════════════
