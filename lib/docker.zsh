#!/usr/bin/env zsh
#
# Docker container management for SpendCloud plugin.

#######################################
# List all SpendCloud dev/cluster containers.
# Globals:
#   SC_DEV_CONTAINER_PATTERN
# Outputs:
#   Container names (one per line) to stdout
# Returns:
#   0 always (empty if no containers)
#######################################
_sc_list_dev_containers() {
  emulate -L zsh ${=${options[xtrace]:#off}:+-o xtrace}
  setopt extended_glob warn_create_global typeset_silent no_short_loops rc_quotes no_auto_pushd
  local MATCH REPLY; integer MBEGIN MEND; local -a match mbegin mend reply

  # Check Docker first to avoid errors
  if ! docker info >/dev/null 2>&1; then
    return 0
  fi

  docker ps -a --format "{{.Names}}" | grep -E "${SC_DEV_CONTAINER_PATTERN}" 2>/dev/null || true
}

#######################################
# Stop and remove containers from stdin list.
# Inputs:
#   Container names from stdin (one per line)
# Outputs:
#   None (errors suppressed)
# Returns:
#   0 always
#######################################
_sc_stop_and_remove_containers() {
  emulate -L zsh ${=${options[xtrace]:#off}:+-o xtrace}
  setopt extended_glob warn_create_global typeset_silent no_short_loops rc_quotes no_auto_pushd
  local MATCH REPLY; integer MBEGIN MEND; local -a match mbegin mend reply

  local names
  names="$(cat)"
  [[ -z "${names}" ]] && return 0
  echo "${names}" | xargs -r docker stop 2>/dev/null || true
  echo "${names}" | xargs -r docker rm 2>/dev/null || true
}

#######################################
# Clean up any existing dev containers before cluster start.
# Outputs:
#   Status messages to stdout
# Returns:
#   0 always
#######################################
_sc_cleanup_existing_containers() {
  emulate -L zsh ${=${options[xtrace]:#off}:+-o xtrace}
  setopt extended_glob warn_create_global typeset_silent no_short_loops rc_quotes no_auto_pushd
  local MATCH REPLY; integer MBEGIN MEND; local -a match mbegin mend reply

  _sc_info "🔍 Checking for existing containers..."
  local containers container
  containers="$(_sc_list_dev_containers | head -15)"

  if [[ -z "${containers}" ]]; then
    _sc_success "No conflicting containers found"
    return 0
  fi

  _sc_warn "Found existing containers that may conflict:"
  while IFS= read -r container; do
    echo "  • ${container}"
  done <<<"${containers}"

  _sc_warn "🛑 Stopping and removing containers..."
  printf '%s' "${containers}" | _sc_stop_and_remove_containers
  _sc_success "Containers stopped and removed"
}

#######################################
# Start a dev service in background.
# Arguments:
#   1 - Service directory path
#   2 - Log file prefix
#   3 - Color code for status message
# Globals:
#   SC_DEV_LOG_DIR
# Outputs:
#   Status messages to stdout
# Returns:
#   0 on success, 1 on failure
#######################################
_sc_start_dev_service() {
  emulate -L zsh ${=${options[xtrace]:#off}:+-o xtrace}
  setopt extended_glob warn_create_global typeset_silent no_short_loops rc_quotes no_auto_pushd
  local MATCH REPLY; integer MBEGIN MEND; local -a match mbegin mend reply

  local service_dir="${1}" log_prefix="${2}" color="${3}"

  if [[ ! -d "${service_dir}" ]]; then
    _sc_warn "Skipping dev start: directory not found (${service_dir})"
    return 0
  fi

  _sc_print "${color}" "⚡ Starting dev for ${log_prefix}..."
  mkdir -p "${SC_DEV_LOG_DIR}"

  (
    cd "${service_dir}" || exit 1
    nohup sct dev >>"${SC_DEV_LOG_DIR}/${log_prefix}.log" 2>&1 &
    echo $! > "${SC_DEV_LOG_DIR}/${log_prefix}.pid"
  ) || {
    _sc_error "Failed to start dev in ${service_dir}"
    return 1
  }

  # Give the process a moment to start
  sleep 1

  # Verify the process is still running
  if [[ -f "${SC_DEV_LOG_DIR}/${log_prefix}.pid" ]]; then
    local pid
    pid="$(cat "${SC_DEV_LOG_DIR}/${log_prefix}.pid")"
    if ! kill -0 "${pid}" 2>/dev/null; then
      _sc_error "Dev service failed to start (process died immediately)"
      return 1
    fi
  fi
}

#######################################
# Start all SpendCloud dev services in background.
# Globals:
#   SC_API_DIR
#   SC_PROACTIVE_DIR
#   SC_DEV_LOG_DIR
# Outputs:
#   Status messages to stdout
# Returns:
#   0 if all services started, 1 if any failed
#######################################
_sc_start_all_dev_services() {
  emulate -L zsh ${=${options[xtrace]:#off}:+-o xtrace}
  setopt extended_glob warn_create_global typeset_silent no_short_loops rc_quotes no_auto_pushd
  local MATCH REPLY; integer MBEGIN MEND; local -a match mbegin mend reply

  sleep 2
  local fail=0

  _sc_start_dev_service "${SC_API_DIR}" "spend-cloud-api" "${C_PURPLE}" || fail=1
  _sc_start_dev_service "${SC_PROACTIVE_DIR}" "proactive-frame" "${C_CYAN}" || fail=1

  if ((fail == 0)); then
    _sc_success "All services started!"
    _sc_print "${C_WHITE}" "🌟 SCT cluster + dev services running in background."
    return 0
  fi

  _sc_warn "Cluster started, but some dev services failed. Check logs in ${SC_DEV_LOG_DIR}."
  return 1
}
