#!/usr/bin/env zsh
#
# Common utilities and constants for SpendCloud plugin.
# Follows Zsh Plugin Standard best practices.

# ════════════════════════════════════════════════════════════════════════════════
# CONSTANTS & CONFIGURATION
# ════════════════════════════════════════════════════════════════════════════════

# Color codes (TTY-aware)
if [[ -z "${C_RESET:-}" ]]; then
  if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    typeset -g C_RED=$'\033[0;31m' C_GREEN=$'\033[0;32m' C_YELLOW=$'\033[1;33m'
    typeset -g C_BLUE=$'\033[0;34m' C_PURPLE=$'\033[0;35m' C_CYAN=$'\033[0;36m'
    typeset -g C_WHITE=$'\033[1;37m' C_RESET=$'\033[0m'
  else
    typeset -g C_RED="" C_GREEN="" C_YELLOW="" C_BLUE="" C_PURPLE="" C_CYAN="" C_WHITE="" C_RESET=""
  fi
fi

# SpendCloud specific configuration
if [[ -z "${SC_DEV_CONTAINER_PATTERN:-}" ]]; then
  typeset -g SC_DEV_CONTAINER_PATTERN='(spend-cloud.*dev|proactive-frame.*dev|api.*dev|ui.*dev|proactive-frame|spend-cloud-api|spend-cloud-ui)'
  typeset -g SC_API_CONTAINER_PATTERN='spend.*cloud.*api|api.*spend.*cloud'
  typeset -g SC_DEV_LOG_DIR="${HOME}/.cache/spend-cloud/logs"
  typeset -g SC_API_DIR="${HOME}/development/spend-cloud/api"
  typeset -g SC_PROACTIVE_DIR="${HOME}/development/proactive-frame"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# UTILITY FUNCTIONS (Reusable across commands)
# ═══════════════════════════════════════════════════════════════════════════════

#######################################
# Print colored output with automatic reset.
# Arguments:
#   1 - Color code (C_RED, C_GREEN, etc.)
#   2 - Message text
# Outputs:
#   Writes colored message to stdout
#######################################
_sc_print() {
  emulate -L zsh ${=${options[xtrace]:#off}:+-o xtrace}
  setopt extended_glob warn_create_global typeset_silent no_short_loops rc_quotes no_auto_pushd
  local MATCH REPLY; integer MBEGIN MEND; local -a match mbegin mend reply

  echo -e "${1}${2}${C_RESET}"
}

#######################################
# Print error message in red with error emoji.
# Arguments:
#   * - Message text
# Outputs:
#   Writes error message to stdout
#######################################
_sc_error() {
  emulate -L zsh ${=${options[xtrace]:#off}:+-o xtrace}
  setopt extended_glob warn_create_global typeset_silent no_short_loops rc_quotes no_auto_pushd
  local MATCH REPLY; integer MBEGIN MEND; local -a match mbegin mend reply

  _sc_print "${C_RED}" "❌ ${*}"
}

#######################################
# Print success message in green with checkmark emoji.
# Arguments:
#   * - Message text
# Outputs:
#   Writes success message to stdout
#######################################
_sc_success() {
  emulate -L zsh ${=${options[xtrace]:#off}:+-o xtrace}
  setopt extended_glob warn_create_global typeset_silent no_short_loops rc_quotes no_auto_pushd
  local MATCH REPLY; integer MBEGIN MEND; local -a match mbegin mend reply

  _sc_print "${C_GREEN}" "✅ ${*}"
}

#######################################
# Print warning message in yellow with warning emoji.
# Arguments:
#   * - Message text
# Outputs:
#   Writes warning message to stdout
#######################################
_sc_warn() {
  emulate -L zsh ${=${options[xtrace]:#off}:+-o xtrace}
  setopt extended_glob warn_create_global typeset_silent no_short_loops rc_quotes no_auto_pushd
  local MATCH REPLY; integer MBEGIN MEND; local -a match mbegin mend reply

  _sc_print "${C_YELLOW}" "⚠️  ${*}"
}

#######################################
# Print info message in cyan.
# Arguments:
#   * - Message text
# Outputs:
#   Writes info message to stdout
#######################################
_sc_info() {
  emulate -L zsh ${=${options[xtrace]:#off}:+-o xtrace}
  setopt extended_glob warn_create_global typeset_silent no_short_loops rc_quotes no_auto_pushd
  local MATCH REPLY; integer MBEGIN MEND; local -a match mbegin mend reply

  _sc_print "${C_CYAN}" "${*}"
}

#######################################
# Verify that a required command exists on PATH.
# Arguments:
#   1 - Command name to check
#   2 - Optional custom error message
# Outputs:
#   Error message to stdout if command not found
# Returns:
#   0 if command exists, 1 otherwise
#######################################
_sc_require_command() {
  emulate -L zsh ${=${options[xtrace]:#off}:+-o xtrace}
  setopt extended_glob warn_create_global typeset_silent no_short_loops rc_quotes no_auto_pushd
  local MATCH REPLY; integer MBEGIN MEND; local -a match mbegin mend reply

  command -v "${1}" >/dev/null 2>&1 || {
    _sc_error "'${1}' command not found. ${2:-Install it and try again.}"
    return 1
  }
}

#######################################
# Check if Docker is running and accessible.
# Outputs:
#   Error message to stdout if Docker unavailable
# Returns:
#   0 if Docker is running, 1 otherwise
#######################################
_sc_check_docker() {
  emulate -L zsh ${=${options[xtrace]:#off}:+-o xtrace}
  setopt extended_glob warn_create_global typeset_silent no_short_loops rc_quotes no_auto_pushd
  local MATCH REPLY; integer MBEGIN MEND; local -a match mbegin mend reply

  if ! command -v docker >/dev/null 2>&1; then
    _sc_error "Docker is not installed. Please install Docker and try again."
    return 1
  fi

  if ! docker info >/dev/null 2>&1; then
    _sc_error "Docker daemon is not running. Please start Docker and try again."
    return 1
  fi

  return 0
}

#######################################
# Find first running container matching a pattern.
# Arguments:
#   1 - Regex pattern to match container names
# Outputs:
#   Container name to stdout if found
# Returns:
#   0 always (empty output if no match)
#######################################
_sc_find_container() {
  emulate -L zsh ${=${options[xtrace]:#off}:+-o xtrace}
  setopt extended_glob warn_create_global typeset_silent no_short_loops rc_quotes no_auto_pushd
  local MATCH REPLY; integer MBEGIN MEND; local -a match mbegin mend reply

  docker ps --format '{{.Names}}' | grep -E "${1}" | head -1
}
