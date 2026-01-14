#!/usr/bin/env zsh
#
# Cluster import command for SpendCloud plugin.

#######################################
# Run cluster import with predefined input and filtered output.
# Arguments:
#   1 - Input line to send to sct (string)
#   2+ - Additional arguments forwarded to sct
# Outputs:
#   Filtered progress messages
# Returns:
#   Exit status from sct command
#######################################
_cluster_import_run_with_input() {
  emulate -L zsh ${=${options[xtrace]:#off}:+-o xtrace}
  setopt extended_glob warn_create_global typeset_silent no_short_loops rc_quotes no_auto_pushd
  local MATCH REPLY; integer MBEGIN MEND; local -a match mbegin mend reply

  local input="${1}"
  shift
  printf '%s\n' "${input}" | sct henk import "$@" 2>&1 | _cluster_import_filter_output
  return ${PIPESTATUS[1]}
}

#######################################
# Run interactive cluster import.
# Arguments:
#   * - Additional arguments forwarded to sct
# Outputs:
#   Delegated command output
# Returns:
#   Exit status from sct command
#######################################
_cluster_import_run_interactive() {
  emulate -L zsh ${=${options[xtrace]:#off}:+-o xtrace}
  setopt extended_glob warn_create_global typeset_silent no_short_loops rc_quotes no_auto_pushd
  local MATCH REPLY; integer MBEGIN MEND; local -a match mbegin mend reply

  sct henk import "$@"
}

#######################################
# Filter and format sct henk import output for clean display.
# Inputs:
#   Raw sct output from stdin
# Outputs:
#   Filtered progress messages to stdout
# Returns:
#   0 on success, 1 if errors detected
#######################################
_cluster_import_filter_output() {
  emulate -L zsh ${=${options[xtrace]:#off}:+-o xtrace}
  setopt extended_glob warn_create_global typeset_silent no_short_loops rc_quotes no_auto_pushd
  local MATCH REPLY; integer MBEGIN MEND; local -a match mbegin mend reply

  local line step="downloading" client_name="" error_msg=""

  while IFS= read -r line; do
    # Extract client name from import line
    if [[ "${line}" == *"Going to import gs://henk-db-dumps/"* ]]; then
      client_name="${line#*henk-db-dumps/}"
      client_name="${client_name%%_*}"
      _sc_info "📦 Downloading ${client_name} database dump..."
      step="downloading"
      continue
    fi

    # Show download progress dots
    if [[ "${step}" == "downloading" && "${line}" == *"."* && "${line}" != *"extracting"* && "${line}" != *"inflating"* ]]; then
      # Show dot every 10th occurrence to avoid flooding
      printf '.' >&2
      continue
    fi

    # Transition to extraction
    if [[ "${line}" == *"Archive:"* || "${line}" == *"extracting"* || "${line}" == *"inflating"* ]]; then
      if [[ "${step}" == "downloading" ]]; then
        printf '\n' >&2
        _sc_info "📂 Extracting database files..."
        step="extracting"
      fi
      continue
    fi

    # Transition to import
    if [[ "${line}" == *"Running "*.sql* ]]; then
      if [[ "${step}" != "importing" ]]; then
        _sc_info "💾 Importing database (this may take a while)..."
        step="importing"
      fi
      continue
    fi

    # Suppress known noise and benign errors
    if [[ "${line}" == *"Loading available customer dumps"* ]] ||
      [[ "${line}" =~ ^[0-9]+\..*gs://henk-db-dumps/ ]] ||
      [[ "${line}" == *"Please choose a dump"* ]] ||
      [[ "${line}" == *"Copying gs://"* ]] ||
      [[ "${line}" == *"Average throughput"* ]] ||
      [[ "${line}" == *"the input device is not a TTY"* ]] ||
      [[ "${line}" == *"Use --trace to view backtrace"* ]] ||
      [[ "${line}" == *"Successfully copied"* ]] ||
      [[ "${line}" == *"Copied db_encryption.key"* ]] ||
      [[ "${line}" == *"Cluster import complete"* ]] ||
      [[ "${line}" == *"Import successful"* ]] ||
      [[ "${line}" == *"Done"* ]] ||
      [[ -z "${line}" ]]; then
      continue
    fi

    # Capture ONLY critical errors (duplicate key errors in core tables)
    if [[ "${line}" =~ "ERROR 1062.*Duplicate entry.*PRIMARY" ]] && [[ "${line}" =~ "(00_settings|client)" ]]; then
      error_msg="${line}"
      _sc_error "${line}"
      continue
    fi

    # Other critical MySQL errors (non-duplicate)
    if [[ "${line}" =~ ^ERROR\ [0-9]+.*at\ line.*in\ file ]] && [[ "${line}" != *"Duplicate entry"* ]]; then
      error_msg="${line}"
      _sc_error "${line}"
    fi
  done

  # Final newline if we were showing dots
  [[ "${step}" == "downloading" ]] && printf '\n' >&2

  # Return error message for caller to use
  [[ -n "${error_msg}" ]] && return 1 || return 0
}

#######################################
# Probe sct for available cluster import targets.
# Arguments:
#   * - Additional arguments forwarded to sct
# Outputs:
#   Raw sct stdout/stderr (with carriage returns removed)
# Returns:
#   Always 0 (errors are handled by caller)
#######################################
_cluster_import_probe() {
  emulate -L zsh ${=${options[xtrace]:#off}:+-o xtrace}
  setopt extended_glob warn_create_global typeset_silent no_short_loops rc_quotes no_auto_pushd
  local MATCH REPLY; integer MBEGIN MEND; local -a match mbegin mend reply

  local -a args
  args=("$@")
  local sentinel="__cluster_wrapper_probe__" output

  # Use raw sct output for probing, bypass the filter
  output="$(printf '%s\n' "${sentinel}" | sct henk import "${args[@]}" 2>&1 || true)"
  output="${output//$'\r'/}"
  printf '%s\n' "${output}"
}

#######################################
# Extract numbered options from sct probe output.
# Outputs:
#   Tab-separated option lines: "NUMBER<TAB>CLIENT_NAME<TAB>TIMESTAMP"
# Returns:
#   0 on success, 1 if no options found
#######################################
_cluster_import_parse_options() {
  emulate -L zsh ${=${options[xtrace]:#off}:+-o xtrace}
  setopt extended_glob warn_create_global typeset_silent no_short_loops rc_quotes no_auto_pushd
  local MATCH REPLY; integer MBEGIN MEND; local -a match mbegin mend reply

  local probe_output="${1}"
  [[ -n "${probe_output}" ]] || return 1

  local parsed num client timestamp
  parsed="$(printf '%s\n' "${probe_output}" | awk '
    BEGIN { FS=""; }
    /^[[:space:]]*[0-9]+[.)][[:space:]]+/ {
      line=$0
      gsub(/\r/, "", line)
      sub(/^[[:space:]]*/, "", line)

      # Extract number (renamed to avoid global warnings)
      num_val=line
      sub(/[[:space:]].*$/, "", num_val)
      sub(/[).]$/, "", num_val)

      # Validate number is actually numeric
      if (num_val !~ /^[0-9]+$/) next

      # Extract full path (gs://henk-db-dumps/...)
      desc=line
      sub(/^[0-9]+[.)][[:space:]]+/, "", desc)

      # Parse client name and timestamp from path
      # Format: gs://henk-db-dumps/CLIENT_YYYY-MM-DDTHH:MM:SS.zip
      if (match(desc, /\/[^_]+_[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.zip/)) {
        # Extract components using sub/gsub
        temp = desc
        sub(/.*\//, "", temp)  # Remove path prefix
        sub(/\.zip.*$/, "", temp)  # Remove .zip suffix

        # Split on underscore: CLIENT_TIMESTAMP
        client_val = temp
        sub(/_.*$/, "", client_val)

        timestamp_raw = temp
        sub(/^[^_]+_/, "", timestamp_raw)

        # Parse YYYY-MM-DDTHH:MM:SS
        split(timestamp_raw, dt, /[-T:]/)
        year = dt[1]
        month = dt[2]
        day = dt[3]
        hour = dt[4]
        min = dt[5]
        sec = dt[6]

        # Compute epoch seconds for sorting (use GNU date)
        epoch_cmd = sprintf("date -d \"%04d-%02d-%02d %02d:%02d:%02d\" +%%s 2>/dev/null || echo 0", year, month, day, hour, min, sec)
        epoch_cmd | getline epoch_val
        close(epoch_cmd)

        # Store as sortable record: epoch, num, client, timestamp_raw
        printf "%s\t%s\t%-18s\t%s\n", epoch_val, num_val, client_val, timestamp_raw
      }
    }
  ' | sort -t$'\t' -k1,1nr | awk -F'\t' '
    BEGIN {
      # Get current time
      cmd = "date +%s"
      cmd | getline now
      close(cmd)

      months = "Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec"
      split(months, month_arr, " ")
    }
    {
      epoch = $1
      num = $2
      client = $3
      timestamp_raw = $4

      # Parse timestamp_raw: YYYY-MM-DDTHH:MM:SS
      split(timestamp_raw, dt, /[-T:]/)
      year = dt[1]
      month = dt[2]
      day = dt[3]
      hour = dt[4]
      min = dt[5]

      # Calculate relative time
      diff = now - epoch
      days_diff = int(diff / 86400)

      if (days_diff == 0) {
        # Today
        hours_diff = int(diff / 3600)
        if (hours_diff == 0) {
          mins_diff = int(diff / 60)
          if (mins_diff == 0) {
            rel = "just now"
          } else if (mins_diff == 1) {
            rel = "1 minute ago"
          } else {
            rel = sprintf("%d minutes ago", mins_diff)
          }
        } else if (hours_diff == 1) {
          rel = "1 hour ago"
        } else {
          rel = sprintf("%d hours ago", hours_diff)
        }
      } else if (days_diff == 1) {
        rel = "yesterday"
      } else if (days_diff < 7) {
        rel = sprintf("%d days ago", days_diff)
      } else if (days_diff < 14) {
        rel = "1 week ago"
      } else if (days_diff < 30) {
        weeks = int(days_diff / 7)
        rel = sprintf("%d weeks ago", weeks)
      } else {
        # Fallback to absolute date
        month_name = month_arr[int(month)]
        rel = sprintf("%s %d, %s", month_name, int(day), year)
      }

      printf "%s\t%-18s\t%s\n", num, client, rel
    }
  ')"

  [[ -n "${parsed}" ]] || return 1
  printf '%s\n' "${parsed}"
}

#######################################
# Extract header line from probe output for display.
# Outputs:
#   First non-empty, non-option line (if any)
# Returns:
#   0 always
#######################################
_cluster_import_header() {
  emulate -L zsh ${=${options[xtrace]:#off}:+-o xtrace}
  setopt extended_glob warn_create_global typeset_silent no_short_loops rc_quotes no_auto_pushd
  local MATCH REPLY; integer MBEGIN MEND; local -a match mbegin mend reply

  local probe_output="${1}"
  [[ -n "${probe_output}" ]] || return 0

  printf '%s\n' "${probe_output}" | awk '
    /^[[:space:]]*[0-9]+[.)][[:space:]]+/ { next }
    /^[[:space:]]*$/ { next }
    /__cluster_wrapper_probe__/ { next }
    /Invalid selection/ { next }
    { print; exit }
  '
}

#######################################
# Interactive wrapper around `sct henk import`.
# Arguments:
#   --client CLIENT_NAME - Optional client name to import directly
#   * - Additional arguments forwarded to sct
# Outputs:
#   Delegated sct output
# Returns:
#   Exit status from sct import command
#######################################
cluster-import() {
  emulate -L zsh ${=${options[xtrace]:#off}:+-o xtrace}
  setopt extended_glob warn_create_global typeset_silent no_short_loops rc_quotes no_auto_pushd
  local MATCH REPLY; integer MBEGIN MEND; local -a match mbegin mend reply

  _sc_require_command sct "Install the SpendCloud CLI (sct)" || return 1

  # Parse --client flag
  local client_name=""
  local -a args
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --client)
        shift
        client_name="$1"
        shift
        ;;
      *)
        args+=("$1")
        shift
        ;;
    esac
  done

  # Check if cluster is running, start it if not
  if ! docker ps --format '{{.Names}}' | grep -q "mysql-service\|proactive-config"; then
    _sc_info "🔍 Cluster not running. Starting cluster..."
    _cluster_start || {
      _sc_error "Failed to start cluster. Cannot import."
      return 1
    }

    # Wait for services to be ready with proper checks
    _sc_info "⏳ Waiting for services to be ready..."
    local retries=0
    local max_retries=30
    while ! docker ps --format '{{.Names}}' | grep -q "mysql-service" && ((retries < max_retries)); do
      sleep 1
      ((retries++))
    done

    if ((retries >= max_retries)); then
      _sc_error "Services did not start in time."
      return 1
    fi

    # Give MySQL extra time to initialize
    sleep 3
    _sc_success "Cluster is ready!"
  fi

  # Fix /data directory permissions for imports (runs as root to ensure it works)
  docker exec proactive-config bash -c "mkdir -p /data && chmod 777 /data" 2>/dev/null || true

  # If --client flag provided, handle direct import
  if [[ -n "${client_name}" ]]; then
    # Check for existing client data before import
    if command -v nuke >/dev/null 2>&1; then
      local container
      container="$(docker ps --format '{{.Names}}' | grep -E '^spend-cloud-api$' | head -1)"

      if [[ -n "${container}" ]]; then
        # Check if client exists in database or has data folder
        local has_residue=0

        # Check database existence (ignore errors - residue checks are best-effort)
        if docker exec "${container}" php artisan tinker --execute="foreach(DB::select('SHOW DATABASES') as \$row) { \$props = get_object_vars(\$row); \$db = reset(\$props); if (stripos(\$db, '${client_name}') === 0) { echo \$db; exit; } }" 2>&1 | grep -qv "error:" | grep -q "."; then
          has_residue=1
        fi

        # Check settings table (ignore errors - residue checks are best-effort)
        if docker exec "${container}" php artisan tinker --execute="use Illuminate\Support\Facades\DB; \$count = DB::connection('mysql_config')->table('00_settings')->whereRaw('LOWER(\`043\`) = ?', [strtolower('${client_name}')])->count(); echo \$count;" 2>&1 | grep -qv "error:" | grep -qv "^0$"; then
          has_residue=1
        fi

        # Check data folder
        if docker exec "${container}" test -d "/data/${client_name}" 2>/dev/null; then
          has_residue=1
        fi

        if ((has_residue == 1)); then
          _sc_warn "⚠️  Found existing data for '${client_name}'"
          _sc_info "Running automatic cleanup before import..."

          # Source nuke if not already loaded
          if ! typeset -f _nuke_execute >/dev/null 2>&1; then
            local plugin_dir="${0:A:h}"
            [[ -f "${plugin_dir}/nuke.zsh" ]] && source "${plugin_dir}/nuke.zsh"
          fi

          # Run nuke with force flag
          if nuke "${client_name}" --force; then
            _sc_success "✓ Cleanup complete, proceeding with import..."
          else
            _sc_error "Cleanup failed. Import may encounter duplicate key errors."
            _sc_info "You can manually run: nuke ${client_name} --force"
          fi
          echo ""
        fi
      fi
    fi

    local probe_output
    probe_output="$(_cluster_import_probe "${args[@]}")"

    local options_text
    if ! options_text="$(_cluster_import_parse_options "${probe_output}")"; then
      _sc_error "Unable to parse SCT cluster list."
      return 1
    fi

    # Find matching client (case-insensitive)
    local matched_number="" matched_timestamp="" num client ts
    while IFS=$'\t' read -r num client ts; do
      # Trim whitespace from client name
      client="${client// /}"
      if [[ "${client:l}" == "${client_name:l}" ]]; then
        matched_number="${num}"
        matched_timestamp="${ts}"
        break
      fi
    done <<<"${options_text}"

    if [[ -z "${matched_number}" ]]; then
      _sc_error "Client '${client_name}' not found in available dumps."
      return 1
    fi

    _sc_info "📥 Importing cluster dataset: ${client_name} (${matched_timestamp})"
    _cluster_import_run_with_input "${matched_number}" "${args[@]}"
    local exit_code=$?

    if ((exit_code == 0)); then
      _sc_success "Cluster import complete."
      return 0
    else
      _sc_error "Cluster import failed."
      return ${exit_code}
    fi
  fi

  if ! command -v fzf >/dev/null 2>&1; then
    _sc_warn "fzf not found; falling back to default SCT prompt."
    _cluster_import_run_interactive "${args[@]}"
    return $?
  fi

  local probe_output
  probe_output="$(_cluster_import_probe "${args[@]}")"

  local options_text
  if ! options_text="$(_cluster_import_parse_options "${probe_output}")"; then
    _sc_warn "Unable to parse SCT cluster list; using default prompt."
    _cluster_import_run_interactive "${args[@]}"
    return $?
  fi

  local header
  header="$(_cluster_import_header "${probe_output}")"
  if [[ -z "${options_text}" ]]; then
    _sc_warn "No cluster import targets detected; using default prompt."
    _cluster_import_run_interactive "${args[@]}"
    return $?
  fi

  local selection
  if [[ -n "${header}" ]]; then
    selection="$(printf '%s\n' "${options_text}" | fzf --prompt='Import cluster > ' --with-nth=2,3 --delimiter=$'\t' --header="${header}" --height=60% --reverse)"
  else
    selection="$(printf '%s\n' "${options_text}" | fzf --prompt='Import cluster > ' --with-nth=2,3 --delimiter=$'\t' --height=60% --reverse)"
  fi

  local exit_code=$?
  if ((exit_code != 0)) || [[ -z "${selection}" ]]; then
    _sc_warn "Cluster import selection cancelled."
    return 130
  fi

  local number client_name timestamp
  IFS=$'\t' read -r number client_name timestamp <<<"${selection}"

  if [[ -n "${client_name}" ]]; then
    _sc_info "📥 Importing cluster dataset: ${client_name} (${timestamp})"
  else
    _sc_info "📥 Importing cluster dataset #${number}"
  fi

  _cluster_import_run_with_input "${number}" "${args[@]}"
  exit_code=$?

  if ((exit_code == 0)); then
    _sc_success "Cluster import complete."
    return 0
  else
    _sc_error "Cluster import failed."
    return ${exit_code}
  fi
}
