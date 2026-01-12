#!/usr/bin/env zsh
#
# SpendCloud / Proactive Frame / Cluster tooling plugin for zsh.
# Compliant with Zsh Plugin Standard and Google Shell Style Guide.
#
# Usage:
#   Add 'spend-cloud' to your plugins array in ~/.zshrc:
#   plugins=(git zsh-autosuggestions ... spend-cloud)
#
#   To disable, simply comment it out or remove from plugins array.
#
# Exposed user-facing commands / aliases (PUBLIC API):
#   Aliases: sc scapi scui cui capi devapi pf cpf
#   Functions: cluster cluster-import migrate nuke
#
# Refactored using clean code principles: DRY, SRP, meaningful names, small functions.
# Modular architecture: each command is in its own file under lib/

# ════════════════════════════════════════════════════════════════════════════════
# PLUGIN INITIALIZATION (Zsh Plugin Standard compliant)
# ════════════════════════════════════════════════════════════════════════════════

# Guard against duplicate loading
if [[ -n "${_SPEND_CLOUD_PLUGIN_LOADED:-}" ]]; then
  return 0
fi
typeset -g _SPEND_CLOUD_PLUGIN_LOADED=1

# Standardized $0 handling (Zsh Plugin Standard section 1)
0="${ZERO:-${${0:#$ZSH_ARGZERO}:-${(%):-%N}}}"
0="${${(M)0:#/*}:-$PWD/$0}"
typeset -g SPEND_CLOUD_PLUGIN_DIR="${0:h}"

# Handle functions/ subdirectory (Zsh Plugin Standard section 2)
if [[ ${zsh_loaded_plugins[-1]} != */spend-cloud && -z ${fpath[(r)${SPEND_CLOUD_PLUGIN_DIR}/functions]} ]]; then
  if [[ -d "${SPEND_CLOUD_PLUGIN_DIR}/functions" ]]; then
    fpath=("${SPEND_CLOUD_PLUGIN_DIR}/functions" "${fpath[@]}")
  fi
fi

# Register with plugin manager activity indicator (Zsh Plugin Standard section 7)
typeset -ga zsh_loaded_plugins
zsh_loaded_plugins+=("${SPEND_CLOUD_PLUGIN_DIR}")

# ════════════════════════════════════════════════════════════════════════════════
# LOAD MODULES
# ════════════════════════════════════════════════════════════════════════════════

source "${SPEND_CLOUD_PLUGIN_DIR}/lib/common.zsh"      # Common utilities and constants
source "${SPEND_CLOUD_PLUGIN_DIR}/lib/docker.zsh"      # Docker container management
source "${SPEND_CLOUD_PLUGIN_DIR}/lib/aliases.zsh"     # Navigation aliases
source "${SPEND_CLOUD_PLUGIN_DIR}/lib/cluster.zsh"     # Cluster lifecycle management
source "${SPEND_CLOUD_PLUGIN_DIR}/lib/cluster-import.zsh"  # Cluster import command
source "${SPEND_CLOUD_PLUGIN_DIR}/lib/migrate.zsh"     # Database migration command
source "${SPEND_CLOUD_PLUGIN_DIR}/lib/nuke.zsh"        # Client cleanup tool
source "${SPEND_CLOUD_PLUGIN_DIR}/lib/hub.zsh"         # Interactive hub command

# ════════════════════════════════════════════════════════════════════════════════
# UNLOAD SUPPORT (Zsh Plugin Standard section 4)
# ════════════════════════════════════════════════════════════════════════════════

#######################################
# Unload the spend-cloud plugin and clean up all resources.
# Globals:
#   SC_DEV_LOG_DIR
#   _SPEND_CLOUD_PLUGIN_LOADED
# Returns:
#   0 always
#######################################
spend_cloud_plugin_unload() {
  emulate -L zsh ${=${options[xtrace]:#off}:+-o xtrace}
  setopt extended_glob warn_create_global typeset_silent no_short_loops rc_quotes no_auto_pushd

  # Unalias all plugin aliases
  unalias sc scapi scui cui capi devapi pf cpf 2>/dev/null

  # Unfunction all public commands
  unfunction cluster cluster-import migrate nuke spend-cloud 2>/dev/null

  # Unfunction all internal functions
  unfunction -m '_sc_*' 2>/dev/null
  unfunction -m '_cluster_*' 2>/dev/null
  unfunction -m '_cluster_import_*' 2>/dev/null
  unfunction -m '_migrate_*' 2>/dev/null
  unfunction -m '_nuke_*' 2>/dev/null
  unfunction -m '_spend_cloud_hub_*' 2>/dev/null

  # Remove from fpath
  fpath=("${(@)fpath:#${SPEND_CLOUD_PLUGIN_DIR}/functions}")
  fpath=("${(@)fpath:#${SPEND_CLOUD_PLUGIN_DIR}}")

  # Clean up globals
  unset _SPEND_CLOUD_PLUGIN_LOADED SPEND_CLOUD_PLUGIN_DIR
  unset SC_DEV_CONTAINER_PATTERN SC_API_CONTAINER_PATTERN
  unset SC_DEV_LOG_DIR SC_API_DIR SC_PROACTIVE_DIR
  unset C_RED C_GREEN C_YELLOW C_BLUE C_PURPLE C_CYAN C_WHITE C_RESET

  # Unload self
  unfunction spend_cloud_plugin_unload
}
