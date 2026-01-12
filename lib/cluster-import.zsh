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

    # Capture actual errors from sct
    if [[ "${line}" =~ ^(Error|ERROR|error:|Errno|RuntimeError|StandardError|Exception|Failed|FAILED) ]]; then
      error_msg="${line}"
      _sc_error "${line}"
      continue
    fi

    # Show completion message
    if [[ "${line}" == *"Cluster import complete"* || "${line}" == *"Import successful"* || "${line}" == *"Done"* ]]; then
      continue
    fi

    # Suppress known noise
    if [[ "${line}" == *"Loading available customer dumps"* ]] ||
      [[ "${line}" =~ ^[0-9]+\..*gs://henk-db-dumps/ ]] ||
      [[ "${line}" == *"Please choose a dump"* ]] ||
      [[ "${line}" == *"Copying gs://"* ]] ||
      [[ "${line}" == *"Average throughput"* ]] ||
      [[ "${line}" == *"the input device is not a TTY"* ]] ||
      [[ "${line}" == *"error: docker exec -it mysql-service"* ]] ||
      [[ "${line}" == *"Use --trace to view backtrace"* ]] ||
      [[ "${line}" == *"Successfully copied"* ]] ||
      [[ "${line}" == *"Copied db_encryption.key"* ]] ||
      [[ -z "${line}" ]]; then
      continue
    fi

    # Catch-all for other potential error indicators
    if [[ "${line}" == *"error"* ]] || [[ "${line}" == *"fail"* ]] || [[ "${line}" == *"Error"* ]]; then
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

  local parsed
  parsed="$(printf '%s\n' "${probe_output}" | awk '
    /^[[:space:]]*[0-9]+[.)][[:space:]]+/ {
      line=$0
      gsub(/\r/, "", line)
      sub(/^[[:space:]]*/, "", line)

      # Extract number
      num=line
      sub(/[[:space:]].*$/, "", num)
      sub(/[).]$/, "", num)

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
        client = temp
        sub(/_.*$/, "", client)

        timestamp_raw = temp
        sub(/^[^_]+_/, "", timestamp_raw)

        # Parse YYYY-MM-DDTHH:MM:SS
        split(timestamp_raw, dt, /[-T:]/)
        year = dt[1]
        month = dt[2]
        day = dt[3]
        hour = dt[4]
        min = dt[5]

        # Format as human-readable: "Sep 30, 2025 11:00"
        months = "Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec"
        split(months, month_arr, " ")
        month_name = month_arr[int(month)]

        timestamp = sprintf("%s %02d, %s %02d:%02d", month_name, int(day), year, int(hour), int(min))

        # Pad client name to 18 characters (right-padded with spaces)
        printf "%s\t%-18s\t%s\n", num, client, timestamp
      }
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

  # Check if cluster is running, start it if not
  if ! docker ps --format '{{.Names}}' | grep -q "mysql-service\|proactive-config"; then
    _sc_info "🔍 Cluster not running. Starting cluster..."
    _cluster_start || {
      _sc_error "Failed to start cluster. Cannot import."
      return 1
    }
    
    # Wait for services to be ready
    _sc_info "⏳ Waiting for services to be ready..."
    sleep 5
    _sc_success "Cluster is ready!"
  fi
  
  # Fix /data directory permissions for imports (runs as root to ensure it works)
  docker exec proactive-config bash -c "mkdir -p /data && chmod 777 /data" 2>/dev/null || true

  if ! command -v fzf >/dev/null 2>&1; then
    _sc_warn "fzf not found; falling back to default SCT prompt."
    _cluster_import_run_interactive "$@"
    return $?
  fi

  local -a args
  args=("$@")

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
