#!/usr/bin/env zsh
#
# Dangerous client cleanup tool for SpendCloud plugin.

typeset -g DB_USERNAME
typeset -g DB_PASSWORD
typeset -g DB_SERVICES_HOST
typeset -g NUKE_CONFIG_DB

#######################################
# Print nuke error message to stderr.
# Arguments:
#   * - Error message text
# Outputs:
#   Writes to stderr
#######################################
_nuke_err() {
  emulate -L zsh ${=${options[xtrace]:#off}:+-o xtrace}
  setopt extended_glob warn_create_global typeset_silent no_short_loops rc_quotes no_auto_pushd
  local MATCH REPLY; integer MBEGIN MEND; local -a match mbegin mend reply

  printf 'ERROR: %s\n' "$*" >&2
}

#######################################
# Print nuke warning message to stderr.
# Arguments:
#   * - Warning message text
# Outputs:
#   Writes to stderr
#######################################
_nuke_warn() {
  emulate -L zsh ${=${options[xtrace]:#off}:+-o xtrace}
  setopt extended_glob warn_create_global typeset_silent no_short_loops rc_quotes no_auto_pushd
  local MATCH REPLY; integer MBEGIN MEND; local -a match mbegin mend reply

  printf 'WARN: %s\n' "$*" >&2
}

#######################################
# Print nuke info message to stdout.
# Arguments:
#   * - Info message text
# Outputs:
#   Writes to stdout
#######################################
_nuke_info() {
  emulate -L zsh ${=${options[xtrace]:#off}:+-o xtrace}
  setopt extended_glob warn_create_global typeset_silent no_short_loops rc_quotes no_auto_pushd
  local MATCH REPLY; integer MBEGIN MEND; local -a match mbegin mend reply

  printf '%s\n' "$*"
}

#######################################
# Prompt user for confirmation.
# Arguments:
#   1 - Prompt text
#   2 - Expected exact response
# Outputs:
#   Prompt to stderr
# Returns:
#   0 if response matches expected, 1 otherwise
#######################################
_nuke_confirm() {
  emulate -L zsh ${=${options[xtrace]:#off}:+-o xtrace}
  setopt extended_glob warn_create_global typeset_silent no_short_loops rc_quotes no_auto_pushd
  local MATCH REPLY; integer MBEGIN MEND; local -a match mbegin mend reply

  local prompt="${1}" expected="${2}" reply
  printf '%s' "${prompt}" >&2
  read -r reply || return 1
  [[ "${reply}" == "${expected}" ]]
}

#######################################
# Get the spend-cloud-api container name.
# Outputs:
#   Container name to stdout if found
# Returns:
#   0 always (empty if not found)
#######################################
_nuke_get_container() {
  emulate -L zsh ${=${options[xtrace]:#off}:+-o xtrace}
  setopt extended_glob warn_create_global typeset_silent no_short_loops rc_quotes no_auto_pushd
  local MATCH REPLY; integer MBEGIN MEND; local -a match mbegin mend reply

  docker ps --format '{{.Names}}' | grep -E '^spend-cloud-api$' | head -1
}

#######################################
# Execute SQL query in API container.
# Arguments:
#   1 - Container name
#   2+ - SQL query
# Globals:
#   DB_USERNAME
#   DB_PASSWORD
#   DB_SERVICES_HOST
#   NUKE_CONFIG_DB
# Outputs:
#   Query results to stdout
# Returns:
#   Exit code from mysql command
#######################################
_nuke_sql() {
  local container="${1}"
  shift
  local -a cmd=(docker exec -i "${container}" bash -lc)
  local mysql_cmd="mysql -u${DB_USERNAME} -h ${DB_SERVICES_HOST}"
  [[ -n "${DB_PASSWORD}" ]] && mysql_cmd+=" -p${DB_PASSWORD}"
  mysql_cmd+=" ${NUKE_CONFIG_DB} -N -e \"$*\""
  "${cmd[@]}" "${mysql_cmd}" 2>/dev/null
}

#######################################
# Get list of eligible client names from multiple sources.
# Arguments:
#   1 - Container name
#   2 - Settings table name
# Outputs:
#   Client names (one per line) to stdout
# Returns:
#   0 always (empty if no clients)
#######################################
_nuke_get_clients() {
  local container="${1}" settings_table="${2}"
  local folder_clients settings_clients db_clients

  folder_clients="$(docker exec "${container}" bash -lc \
    'ls -1 /data 2>/dev/null | grep -Ev "^(test|lost\+found)$"' || true)"

  settings_clients="$(_nuke_sql "${container}" \
    "SELECT DISTINCT \`043\` FROM ${settings_table} WHERE \`043\` IS NOT NULL AND \`043\` != ''" |
    tr '[:upper:]' '[:lower:]' || true)"

  # Also check for existing databases using Laravel's tinker
  db_clients="$(docker exec "${container}" php artisan tinker --execute="echo implode(PHP_EOL, array_map(fn(\$db) => \$db->Database, DB::select('SHOW DATABASES')));" 2>/dev/null |
    grep -Ev '^(information_schema|mysql|performance_schema|sys|proactive_config|proactive-default|sharedStorage|sharedStorageTesting|spend-cloud|spend-cloud-config|keycloak|testing|testing_frame_dbunit|OCR|addresses)$' || true)"

  printf '%s\n%s\n%s\n' "${folder_clients}" "${settings_clients}" "${db_clients}" |
    awk 'NF' | sort -u |
    grep -Ev '^(proactive_accounts\.ini|spend-cloud|oci)$' || true
}

#######################################
# Interactively select client from list.
# Arguments:
#   1 - Newline-separated client list
# Globals:
#   C_CYAN, C_RESET (for non-fzf mode)
# Outputs:
#   Selected client name to stdout
#   Selection prompt to stderr (if not using fzf)
# Returns:
#   0 always (empty if no selection)
#######################################
_nuke_select_client() {
  local filtered="${1}"
  local target

  if command -v fzf >/dev/null 2>&1; then
    target="$(echo "${filtered}" | fzf --prompt="Select client > ")"
  else
    _nuke_info "${C_CYAN}Select client:${C_RESET}" >&2
    local -a selection
    local i=1 choice
    readarray -t selection <<<"${filtered}"
    for choice in "${selection[@]}"; do
      printf '%2d) %s\n' "${i}" "${choice}" >&2
      ((i++))
    done
    printf 'Enter number: ' >&2
    local num
    read -r num
    if [[ "${num}" =~ ^[0-9]+$ ]] && ((num >= 1 && num < i)); then
      target="${selection[num - 1]}"
    fi
  fi

  echo "${target}"
}

#######################################
# Analyze client data across all sources.
# Arguments:
#   1 - Container name
#   2 - Client name
#   3 - Settings table name
# Globals:
#   C_CYAN, C_RESET
# Outputs:
#   Analysis report to stdout
#   Encoded analysis string (last line) for parsing
# Returns:
#   0 always
#######################################
_nuke_analyze() {
  local container="${1}" target="${2}" settings_table="${3}"
  local client_id has_folder=0 has_settings=0 has_client_row=0 dbs

  # Get databases matching the client name using Laravel tinker
  # The result property is named after the query pattern, so we access it dynamically
  dbs="$(docker exec "${container}" php artisan tinker --execute="foreach(DB::select('SHOW DATABASES') as \$row) { \$props = get_object_vars(\$row); \$db = reset(\$props); if (stripos(\$db, '${target}') === 0) { echo \$db . PHP_EOL; } }" 2>/dev/null | grep -v '^$' || true)"

  local folder_clients settings_clients
  folder_clients="$(docker exec "${container}" bash -lc 'ls -1 /data 2>/dev/null' || true)"

  # Check settings using tinker (case-insensitive)
  settings_clients="$(docker exec "${container}" php artisan tinker --execute="use Illuminate\Support\Facades\DB; \$result = DB::connection('mysql_config')->table('${settings_table}')->whereRaw('LOWER(\`043\`) IS NOT NULL')->pluck('043'); echo implode(PHP_EOL, \$result->toArray());" 2>/dev/null || true)"

  echo "${folder_clients}" | grep -Fx "${target}" >/dev/null && has_folder=1
  echo "${settings_clients}" | grep -Fix "${target}" >/dev/null && has_settings=1

  _nuke_info "${C_CYAN}Analysis for '${target}':${C_RESET}" >&2
  printf '  - /data folder: %s\n' "$([[ ${has_folder} -eq 1 ]] && echo present || echo absent)" >&2
  printf '  - %s entry: %s\n' "${settings_table}" "$([[ ${has_settings} -eq 1 ]] && echo present || echo absent)" >&2
  printf '  - 00_client row: %s\n' "$([[ ${has_client_row} -eq 1 ]] && echo present || echo absent)" >&2

  if [[ -n "${dbs}" ]]; then
    _nuke_info '  - databases:' >&2
    local _db
    while IFS= read -r _db; do
      printf '      * %s\n' "${_db}" >&2
    done <<<"${dbs}"
  else
    _nuke_info '  - databases: none' >&2
  fi

  echo "${has_folder}:${has_settings}:${has_client_row}:${dbs}:${client_id}"
}

#######################################
# Execute destructive client cleanup.
# Arguments:
#   1 - Container name
#   2 - Client name
#   3 - Settings table name
#   4 - Analysis string from _nuke_analyze
# Globals:
#   C_RED, C_GREEN, C_RESET
# Outputs:
#   Execution status messages to stdout
# Returns:
#   0 always
#######################################
_nuke_execute() {
  local container="${1}" target="${2}" settings_table="${3}" analysis="${4}"
  local -a analysis_parts
  analysis_parts=("${(@s/:/)analysis}")

  integer has_folder=0 has_settings=0 has_client_row=0
  has_folder=${analysis_parts[1]:-0}
  has_settings=${analysis_parts[2]:-0}
  has_client_row=${analysis_parts[3]:-0}
  local dbs="${analysis_parts[4]:-}"
  local client_id="${analysis_parts[5]:-}"

  _nuke_info "${C_RED}Executing NUKE...${C_RESET}"

  # Drop databases
  if [[ -n "${dbs}" ]]; then
    local db
    while IFS= read -r db; do
      [[ -z "${db}" ]] && continue
      # Validate database name doesn't contain dangerous characters
      if [[ "${db}" =~ [\;\&\|\$\`] ]]; then
        _nuke_warn "  - skipping unsafe db name: ${db}"
        continue
      fi
      _nuke_info "  - drop db ${db}"
      # Use Laravel tinker for database operations since mysql command path issues
      docker exec "${container}" php artisan tinker --execute="DB::statement('DROP DATABASE IF EXISTS \`${db}\`');" >/dev/null 2>&1 ||
        _nuke_warn "    (warn) drop failed ${db}"
    done <<<"${dbs}"
  fi

  # Purge settings (using Laravel tinker for database operations)
  ((has_settings == 1)) && {
    _nuke_info "  - purge ${settings_table}"
    docker exec "${container}" php artisan tinker --execute="use Illuminate\Support\Facades\DB; DB::connection('mysql_config')->table('${settings_table}')->whereRaw('LOWER(\`043\`) = ?', [strtolower('${target}')])->delete();" >/dev/null 2>&1 ||
      _nuke_warn "    (warn) purge failed"
  }

  # Delete from client table to prevent Laravel from recreating the database
  _nuke_info "  - remove from client registry"
  local client_id_result
  client_id_result="$(docker exec "${container}" php artisan tinker --execute="use Illuminate\Support\Facades\DB; \$client = DB::connection('mysql_config')->table('client')->where('naam', '${target}')->orWhereRaw('LOWER(naam) = ?', [strtolower('${target}')])->first(); if(\$client) { echo \$client->id; DB::connection('mysql_config')->table('client')->where('id', \$client->id)->delete(); }" 2>/dev/null)"

  # Clean up all module settings tables (01_settings, 02_settings, etc.) if we found a client_id
  if [[ -n "${client_id_result}" && "${client_id_result}" =~ ^[0-9]+$ ]]; then
    _nuke_info "  - purge module settings (client_id: ${client_id_result})"
    docker exec "${container}" php artisan tinker --execute="use Illuminate\Support\Facades\DB; \$tables = ['01_settings', '02_settings', '03_settings', '04_settings', '05_settings', '06_settings', '07_settings', '08_settings']; foreach(\$tables as \$table) { try { DB::connection('mysql_config')->table(\$table)->where('client_id', ${client_id_result})->delete(); } catch(\Exception \$e) {} }" >/dev/null 2>&1
  fi

  # Remove data folder
  docker exec "${container}" test -d "/data/${target}" && {
    docker exec "${container}" rm -rf "/data/${target}" &&
      _nuke_info "  - removed /data/${target}" ||
      _nuke_warn "  - (warn) folder removal failed"
  }

  _nuke_info "${C_GREEN}Done! Client '${target}' has been nuked.${C_RESET}"
  echo ""
  _nuke_info "Next steps:"
  _nuke_info "  1. Verify cleanup: nuke --verify ${target}"
  _nuke_info "  2. Reimport data: cluster-import --client ${target}"
}

#######################################
# Display nuke command usage.
# Outputs:
#   Help text to stdout
#######################################
_nuke_help() {
  cat <<'EOF'
Usage: nuke [--verify] [clientName]
  --verify | -v   Analyze only; no destructive actions
  --force  | -f   Skip confirmation prompts (USE WITH CAUTION!)
  --help   | -h   Show this help
  clientName      Target client (if omitted, interactive selection)

Environment vars:
  ENABLE_NUKE=1   REQUIRED - Safety flag to enable nuke command
  DB_USERNAME     Database user (default: root)
  DB_PASSWORD     Database password (default: <empty>)
  DB_SERVICES_HOST Database host (default: mysql-service)
  NUKE_CONFIG_DB  Config database name (default: spend-cloud-config)

Description:
  Performs a DESTRUCTIVE cleanup for a client across:
    • Config DB row(s) in settings tables
    • 00_client row & related tables
    • Per-client databases
    • /data/<client> folder

Safety:
  • Requires ENABLE_NUKE=1 environment variable
  • Dual confirmation prompts (can skip with --force)
  • Blacklist of protected names (prod, production, etc.)
  • Verify mode for safe inspection (--verify)

Workflow:
  1. Check what will be deleted:
     → export ENABLE_NUKE=1
     → nuke --verify sherpa

  2. Delete and reimport:
     → nuke sherpa
     → cluster-import --client sherpa

Common use cases:
  • Corrupted database after failed migration
  • Incomplete cluster import
  • Testing with fresh data
  • Removing old/unused clients

⚠️  WARNING: This is DESTRUCTIVE and cannot be undone!
    Always use --verify first to see what will be deleted.

Examples:
  nuke --verify sherpa          # Analyze sherpa without changes
  nuke sherpa                   # Interactive delete with confirmations
  ENABLE_NUKE=1 nuke --force sherpa  # Delete without prompts (DANGEROUS!)
EOF
}

#######################################
# DANGEROUS multi-tenant client cleanup tool.
# Performs destructive cleanup across databases, settings, and filesystem.
# Arguments:
#   [--verify|-v] - Analyze only, no destructive actions
#   [--help|-h]   - Show usage
#   [clientName]  - Target client (interactive if omitted)
# Globals:
#   ENABLE_NUKE (required to be set for execution)
#   DB_USERNAME, DB_PASSWORD, DB_SERVICES_HOST, NUKE_CONFIG_DB
# Outputs:
#   Analysis and execution status to stdout
#   Errors to stderr
# Returns:
#   0 on success/safe abort, 1-5 on errors, 99 if ENABLE_NUKE not set
#######################################
nuke() {
  emulate -L zsh ${=${options[xtrace]:#off}:+-o xtrace}
  setopt extended_glob warn_create_global typeset_silent no_short_loops rc_quotes no_auto_pushd
  local MATCH REPLY; integer MBEGIN MEND; local -a match mbegin mend reply

  [[ -z "${ENABLE_NUKE:-}" ]] && {
    echo "Refusing to run: set ENABLE_NUKE=1 to allow nuke (export ENABLE_NUKE=1)" >&2
    return 99
  }

  # Set defaults
  : "${DB_USERNAME:=root}" "${DB_PASSWORD:=}" "${DB_SERVICES_HOST:=mysql-service}" "${NUKE_CONFIG_DB:=spend-cloud-config}"

  local mode="normal" target="" container settings_table="00_settings" force_mode=0
  local -r blacklist_regex='^(prod|production|shared|sharedstorage|system|default|oci)$'

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "${1}" in
    --verify | -v)
      mode="verify"
      shift
      ;;
    --force | -f)
      force_mode=1
      shift
      ;;
    --help | -h)
      _nuke_help
      return 0
      ;;
    --)
      shift
      break
      ;;
    -*)
      _nuke_err "Unknown flag: ${1}"
      _nuke_help
      return 2
      ;;
    *)
      [[ -z "${target}" ]] && target="${1}" || {
        _nuke_err "Unexpected extra arg: ${1}"
        return 2
      }
      shift
      ;;
    esac
  done

  # Get container
  container="$(_nuke_get_container)" || {
    _nuke_err "API container not running"
    return 3
  }

  # Detect settings table
  _nuke_sql "${container}" "SHOW TABLES LIKE 'client_settings'" | grep -q '^client_settings$' &&
    settings_table='client_settings'

  # Get eligible clients
  local filtered
  filtered="$(_nuke_get_clients "${container}" "${settings_table}")"
  [[ -z "${filtered}" ]] && {
    _nuke_warn "No eligible clients to operate on."
    return 0
  }

  # Select target if not provided
  [[ -z "${target}" ]] && {
    target="$(_nuke_select_client "${filtered}")"
    [[ -z "${target}" ]] && {
      _nuke_warn "No client selected"
      return 0
    }
  }

  # Trim whitespace from target
  target="${target// /}"

  # Validate target is not empty after trimming
  if [[ -z "${target}" ]]; then
    _nuke_err "Invalid target: empty after trimming"
    return 2
  fi

  # Validate target
  [[ "${target}" =~ ${blacklist_regex} ]] && {
    _nuke_err "Target '${target}' is protected"
    return 4
  }
  echo "${filtered}" | grep -Fx "${target}" >/dev/null || {
    _nuke_err "Target '${target}' not in candidate list"
    return 5
  }

  # Analyze
  local analysis
  analysis="$(_nuke_analyze "${container}" "${target}" "${settings_table}")"

  # Verify mode: exit after analysis
  [[ "${mode}" == "verify" ]] && {
    _nuke_info "${C_GREEN}Verify mode: no changes made.${C_RESET}"
    return 0
  }

  # Skip confirmations in force mode
  if ((force_mode == 1)); then
    _nuke_warn "${C_YELLOW}⚠️  FORCE MODE: Skipping confirmations!${C_RESET}"
  else
    # Confirm destruction
    _nuke_confirm "${C_YELLOW}Proceed to NUKE '${target}'? (yes/no) ${C_RESET}" 'yes' || {
      _nuke_info "${C_GREEN}Aborted.${C_RESET}"
      return 0
    }
    _nuke_confirm "${C_RED}Type the client name to confirm: ${C_RESET}" "${target}" || {
      _nuke_info "${C_GREEN}Mismatch. Aborted.${C_RESET}"
      return 1
    }
  fi

  # Execute destruction
  _nuke_execute "${container}" "${target}" "${settings_table}" "${analysis}"
}
