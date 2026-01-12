#!/usr/bin/env zsh
#
# Interactive hub command for SpendCloud plugin.

#######################################
# Display help for spend-cloud hub command.
# Outputs:
#   Help text to stdout
#######################################
_spend_cloud_hub_help() {
  cat <<'EOF'
SpendCloud Plugin Hub
Usage: spend-cloud [--help|-h]

Interactive command hub for the SpendCloud plugin.
Presents a menu of available commands to choose from.

Available commands:
  cluster           Manage cluster lifecycle and dev services
  cluster-import    Interactive database import with fzf
  migrate           Handle database migrations
  nuke              Client cleanup tool (requires ENABLE_NUKE=1)

Options:
  -h, --help        Display this help text

Without options, launches an interactive menu to select a command.
EOF
}

#######################################
# Get list of available commands with descriptions.
# Outputs:
#   Tab-separated lines: "COMMAND<TAB>DESCRIPTION"
# Returns:
#   0 always
#######################################
_spend_cloud_hub_commands() {
  emulate -L zsh ${=${options[xtrace]:#off}:+-o xtrace}
  setopt extended_glob warn_create_global typeset_silent no_short_loops rc_quotes no_auto_pushd
  local MATCH REPLY; integer MBEGIN MEND; local -a match mbegin mend reply

  cat <<'EOF'
cluster	Start/stop cluster and dev services
cluster --rebuild	Rebuild cluster with fresh images
cluster stop	Stop all cluster services
cluster logs	View cluster logs
cluster-import	Import database from available dumps
migrate	Run all database migrations
migrate debug	Run migrations with detailed output
migrate status	Show migration status
nuke --verify	Analyze client data (safe, read-only)
EOF
}

#######################################
# Interactive command selection using fzf.
# Outputs:
#   Selected command to stdout
# Returns:
#   0 if selection made, 1 if cancelled
#######################################
_spend_cloud_hub_select() {
  emulate -L zsh ${=${options[xtrace]:#off}:+-o xtrace}
  setopt extended_glob warn_create_global typeset_silent no_short_loops rc_quotes no_auto_pushd
  local MATCH REPLY; integer MBEGIN MEND; local -a match mbegin mend reply

  local commands selection

  commands="$(_spend_cloud_hub_commands)"

  if command -v fzf >/dev/null 2>&1; then
    # Use fzf for interactive selection
    selection="$(printf '%s\n' "${commands}" | fzf \
      --prompt='SpendCloud > ' \
      --header='Select a command to execute' \
      --with-nth=2 \
      --delimiter=$'\t' \
      --height=60% \
      --reverse \
      --preview='echo {}' \
      --preview-window=hidden \
      --border \
      --color='header:italic:cyan,prompt:bold:green')"
  else
    # Fallback to simple numbered menu
    _sc_info "Available commands:"
    echo ""

    local -a menu_items
    local i=1 cmd desc
    while IFS=$'\t' read -r cmd desc; do
      printf '%s%2d)%s %s%s%s - %s\n' \
        "${C_CYAN}" "$i" "${C_RESET}" \
        "${C_GREEN}" "$cmd" "${C_RESET}" \
        "$desc"
      menu_items+=("$cmd")
      ((i++))
    done <<<"${commands}"

    echo ""
    printf '%sEnter number (or q to quit): %s' "${C_YELLOW}" "${C_RESET}"

    local choice
    read -r choice

    if [[ "${choice}" == "q" ]] || [[ -z "${choice}" ]]; then
      return 1
    fi

    if [[ "${choice}" =~ ^[0-9]+$ ]] && ((choice >= 1 && choice <= ${#menu_items[@]})); then
      selection="${menu_items[choice]}"$'\t'"description"
    else
      _sc_error "Invalid selection: ${choice}"
      return 1
    fi
  fi

  [[ -z "${selection}" ]] && return 1

  # Extract command (first field)
  local command
  command="$(printf '%s' "${selection}" | cut -f1)"

  printf '%s' "${command}"
  return 0
}

#######################################
# Execute a selected command.
# Arguments:
#   1 - Command string to execute
# Returns:
#   Exit code from executed command
#######################################
_spend_cloud_hub_execute() {
  emulate -L zsh ${=${options[xtrace]:#off}:+-o xtrace}
  setopt extended_glob warn_create_global typeset_silent no_short_loops rc_quotes no_auto_pushd
  local MATCH REPLY; integer MBEGIN MEND; local -a match mbegin mend reply

  local cmd="$1"
  [[ -z "${cmd}" ]] && return 1

  _sc_info "Executing: ${cmd}"
  echo ""

  # Execute the command
  eval "${cmd}"
}

#######################################
# Main hub command for SpendCloud plugin.
# Arguments:
#   --help|-h - Show help text
# Outputs:
#   Interactive menu or help text
# Returns:
#   0 on success, 1 on error or cancellation
#######################################
spend-cloud() {
  emulate -L zsh ${=${options[xtrace]:#off}:+-o xtrace}
  setopt extended_glob warn_create_global typeset_silent no_short_loops rc_quotes no_auto_pushd
  local MATCH REPLY; integer MBEGIN MEND; local -a match mbegin mend reply

  # Parse arguments
  case "${1:-}" in
    -h|--help)
      _spend_cloud_hub_help
      return 0
      ;;
    "")
      # No arguments - show interactive menu
      ;;
    *)
      _sc_error "Unknown option: ${1}"
      echo "Run: spend-cloud --help"
      return 1
      ;;
  esac

  # Show interactive selection
  local selected_cmd
  selected_cmd="$(_spend_cloud_hub_select)" || {
    _sc_warn "Selection cancelled."
    return 1
  }

  # Execute the selected command
  _spend_cloud_hub_execute "${selected_cmd}"
}
