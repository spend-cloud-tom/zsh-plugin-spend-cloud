#!/usr/bin/env zsh
#
# Cluster import command for SpendCloud plugin.
#
# IMPORTANT - why this file never pipes stdin:
#   `sct henk import` shells out to `gcloud storage`, and gcloud will only run
#   its reauthentication challenge when BOTH stdin and stderr are TTYs
#   (googlecloudsdk/core/console/console_io.py: CanPrompt -> IsInteractive).
#   Feeding sct a here-string/pipe, or folding stderr into a pipe with `2>&1`,
#   turns an ordinary "Reauthentication required. Please enter your password:"
#   prompt into a hard failure:
#     ERROR: (gcloud.storage.ls) There was a problem refreshing your current
#     auth tokens: Reauthentication failed. cannot prompt during
#     non-interactive execution.
#   The same applies to the `docker exec -it` that `sct henk list-clients` runs.
#   So: capture stdout if you must, but leave stdin and stderr on the terminal.

# Bucket holding the customer database dumps.
if [[ -z "${SC_HENK_DUMP_BUCKET:-}" ]]; then
  typeset -g SC_HENK_DUMP_BUCKET="gs://henk-db-dumps"
fi

#######################################
# List available dumps straight from GCS.
# Only stdout is captured; stdin and stderr stay attached to the terminal so
# gcloud can prompt for reauthentication and surface its own errors.
# Outputs:
#   One gs:// URL per line
# Returns:
#   0 on success, 1 if gcloud failed (auth, network, permissions, ...)
#######################################
_cluster_import_list_dumps() {
  emulate -L zsh ${=${options[xtrace]:#off}:+-o xtrace}
  setopt extended_glob warn_create_global typeset_silent no_short_loops rc_quotes no_auto_pushd
  local MATCH REPLY; integer MBEGIN MEND; local -a match mbegin mend reply

  local listing
  listing="$(gcloud storage ls "${SC_HENK_DUMP_BUCKET}/")" || return 1

  printf '%s\n' "${listing//$'\r'/}"
}

#######################################
# Turn raw gs:// URLs into sorted, human readable selection rows.
# Arguments:
#   1 - Raw listing (one gs:// URL per line)
# Outputs:
#   Tab separated rows, newest first: "URL<TAB>CLIENT<TAB>RELATIVE_TIME"
# Returns:
#   0 on success, 1 if nothing parseable was found
#######################################
_cluster_import_format_dumps() {
  emulate -L zsh ${=${options[xtrace]:#off}:+-o xtrace}
  setopt extended_glob warn_create_global typeset_silent no_short_loops rc_quotes no_auto_pushd
  local MATCH REPLY; integer MBEGIN MEND; local -a match mbegin mend reply

  local listing="${1}"
  [[ -n "${listing}" ]] || return 1

  local formatted
  formatted="$(printf '%s\n' "${listing}" | awk '
    BEGIN {
      cmd = "date +%s"; cmd | getline now; close(cmd)
      split("Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec", month_arr, " ")
    }
    {
      line = $0
      gsub(/\r/, "", line)
      if (line !~ /\.zip$/) next

      base = line
      sub(/.*\//, "", base)
      sub(/\.zip$/, "", base)

      # Split on the LAST underscore: client names may contain underscores,
      # the ISO-8601 timestamp never does.
      cut = 0
      for (j = length(base); j > 0; j--) {
        if (substr(base, j, 1) == "_") { cut = j; break }
      }
      if (cut == 0) next

      client = substr(base, 1, cut - 1)
      ts     = substr(base, cut + 1)
      if (ts !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]$/) next

      split(ts, dt, /[-T:]/)
      epoch = 0
      epoch_cmd = sprintf("date -d \"%s-%s-%s %s:%s:%s\" +%%s 2>/dev/null || echo 0", dt[1], dt[2], dt[3], dt[4], dt[5], dt[6])
      epoch_cmd | getline epoch
      close(epoch_cmd)

      diff = now - epoch
      days = int(diff / 86400)

      if (epoch == 0) {
        rel = ts
      } else if (days == 0) {
        hours = int(diff / 3600)
        if (hours == 0) {
          mins = int(diff / 60)
          if (mins <= 0)       rel = "just now"
          else if (mins == 1)  rel = "1 minute ago"
          else                 rel = sprintf("%d minutes ago", mins)
        }
        else if (hours == 1)   rel = "1 hour ago"
        else                   rel = sprintf("%d hours ago", hours)
      }
      else if (days == 1)      rel = "yesterday"
      else if (days < 7)       rel = sprintf("%d days ago", days)
      else if (days < 14)      rel = "1 week ago"
      else if (days < 30)      rel = sprintf("%d weeks ago", int(days / 7))
      else                     rel = sprintf("%s %d, %s", month_arr[int(dt[2])], int(dt[3]), dt[1])

      printf "%s\t%s\t%s\t%s\n", epoch, line, client, rel
    }
  ' | sort -t$'\t' -k1,1nr | cut -f2-)"

  [[ -n "${formatted}" ]] || return 1
  printf '%s\n' "${formatted}"
}

#######################################
# Format sct henk import output for clean display.
# Only sct's stdout is piped in; stderr stays on the terminal (see file header),
# so gcloud/unzip progress and prompts are shown raw and unfiltered.
# Unrecognised lines are passed through rather than swallowed, so a failing
# import is never silent.
# Inputs:
#   sct stdout from stdin
# Outputs:
#   Formatted progress messages
# Returns:
#   0 on success, 1 if an error line was seen
#######################################
_cluster_import_filter_output() {
  emulate -L zsh ${=${options[xtrace]:#off}:+-o xtrace}
  setopt extended_glob warn_create_global typeset_silent no_short_loops rc_quotes no_auto_pushd
  local MATCH REPLY; integer MBEGIN MEND; local -a match mbegin mend reply

  local line client_name="" saw_error=0
  local step=""

  while IFS= read -r line; do
    # Strip ANSI colours sct emits, so matching is reliable.
    line="${line//$'\r'/}"
    local plain="${line//$'\033'\[[0-9;]#m/}"

    case "${plain}" in
      *"Going to import "*)
        client_name="${plain##*/}"
        client_name="${client_name%_*}"
        _sc_info "📦 Downloading ${client_name} database dump..."
        continue
        ;;
      "Archive:"*|*" inflating:"*|*" extracting:"*)
        if [[ "${step}" != "extracting" ]]; then
          _sc_info "📂 Extracting database files..."
          step="extracting"
        fi
        continue
        ;;
      "Running "*.sql*)
        if [[ "${step}" != "importing" ]]; then
          _sc_info "💾 Importing database (this may take a while)..."
          step="importing"
        fi
        # Keep the per-file "(3/12)" progress, it is the only sign of life.
        _sc_print "${C_BLUE}" "   ${plain}"
        continue
        ;;
      *"Customer already exists"*|"Dropping database"*|"Removing customer"*|"Finding client_id"*|"  Deleting from"*|"  Cleaning up"*)
        _sc_print "${C_BLUE}" "   ${plain}"
        continue
        ;;
      "Finished importing "*)
        _sc_success "${plain}"
        continue
        ;;
      "Loading available customer dumps"*|"Copying gs://"*|*"Average throughput"*|*"Successfully copied"*|"")
        continue
        ;;
      ERROR*|*"ERROR "[0-9]*)
        saw_error=1
        _sc_error "${plain}"
        continue
        ;;
    esac

    # Anything unrecognised is shown as-is. Silence here is what made a broken
    # import look like a successful one.
    printf '%s\n' "${line}"
  done

  return ${saw_error}
}

#######################################
# Detect leftover data for a client before importing over it.
#
# NOTE: this used to read
#   ... | grep -qv "error:" | grep -q "."
# which can never be true: `grep -q` prints nothing, so the second grep always
# sees an empty stream. The database and settings probes were dead code and
# only the /data folder test ever set the flag. Capture and inspect the output
# instead.
#
# Arguments:
#   1 - Container running artisan (spend-cloud-api)
#   2 - Client name
# Returns:
#   0 if residue was found, 1 otherwise
#######################################
_cluster_import_has_residue() {
  emulate -L zsh ${=${options[xtrace]:#off}:+-o xtrace}
  setopt extended_glob warn_create_global typeset_silent no_short_loops rc_quotes no_auto_pushd
  local MATCH REPLY; integer MBEGIN MEND; local -a match mbegin mend reply

  local container="${1}" client="${2}"

  # A client database whose name starts with the client name.
  # tinker appends an "INFO  Goodbye." banner, so only the first line counts.
  local db_match
  db_match="$(docker exec "${container}" php artisan tinker --execute="foreach(DB::select('SHOW DATABASES') as \$row) { \$props = get_object_vars(\$row); \$db = reset(\$props); if (stripos(\$db, '${client}') === 0) { echo \$db; exit; } }" 2>/dev/null | head -1)"
  db_match="${db_match//[[:space:]]/}"
  if [[ -n "${db_match}" && "${db_match}" != *INFO* && "${db_match}" != *error:* ]]; then
    return 0
  fi

  # A row for this client in the shared config table.
  local settings_count
  settings_count="$(docker exec "${container}" php artisan tinker --execute="use Illuminate\Support\Facades\DB; \$count = DB::connection('mysql_config')->table('00_settings')->whereRaw('LOWER(\`043\`) = ?', [strtolower('${client}')])->count(); echo \$count;" 2>/dev/null | head -1)"
  settings_count="${settings_count//[^0-9]/}"
  if [[ -n "${settings_count}" ]] && ((settings_count > 0)); then
    return 0
  fi

  # A leftover shared-storage folder.
  if docker exec "${container}" test -d "/data/${client}" 2>/dev/null; then
    return 0
  fi

  return 1
}

#######################################
# Run the actual import for a dump URL.
# stdin and stderr are deliberately left on the terminal (see file header).
# Arguments:
#   1 - gs:// dump URL
#   2+ - Additional arguments forwarded to sct
# Returns:
#   sct's exit status, or 1 if the output filter saw an error
#######################################
_cluster_import_run() {
  emulate -L zsh ${=${options[xtrace]:#off}:+-o xtrace}
  setopt extended_glob warn_create_global typeset_silent no_short_loops rc_quotes no_auto_pushd
  local MATCH REPLY; integer MBEGIN MEND; local -a match mbegin mend reply

  local url="${1}"
  shift

  local -a status_list
  sct henk import "$@" "${url}" | _cluster_import_filter_output
  # NOTE: zsh populates `pipestatus`, not bash's `PIPESTATUS`. Using the latter
  # silently returned the *filter's* status and reported failed imports as OK.
  status_list=("${pipestatus[@]}")

  (( status_list[1] != 0 )) && return ${status_list[1]}
  return ${status_list[2]}
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
  _sc_require_command gcloud "Install the Google Cloud SDK" || return 1

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

  # If --client was given, clear out any residue for that client first.
  if [[ -n "${client_name}" ]] && command -v nuke >/dev/null 2>&1; then
    local container
    container="$(docker ps --format '{{.Names}}' | grep -E '^spend-cloud-api$' | head -1)"

    if [[ -n "${container}" ]] && _cluster_import_has_residue "${container}" "${client_name}"; then
      _sc_warn "⚠️  Found existing data for '${client_name}'"
      _sc_info "Running automatic cleanup before import..."

      if nuke "${client_name}" --force; then
        _sc_success "✓ Cleanup complete, proceeding with import..."
      else
        _sc_error "Cleanup failed. Import may encounter duplicate key errors."
        _sc_info "You can manually run: nuke ${client_name} --force"
      fi
      echo ""
    fi
  fi

  # List dumps ourselves instead of driving sct's interactive menu through a
  # pipe. gcloud keeps the terminal here, so if the session needs
  # reauthentication it can simply ask for the password.
  local listing
  if ! listing="$(_cluster_import_list_dumps)"; then
    _sc_error "Could not list dumps from ${SC_HENK_DUMP_BUCKET}/ (see the gcloud error above)."
    _sc_info "If gcloud asked you to reauthenticate, run: ${C_WHITE}gcloud auth login${C_RESET}"
    return 1
  fi

  local options_text
  if ! options_text="$(_cluster_import_format_dumps "${listing}")"; then
    _sc_error "No usable dumps found in ${SC_HENK_DUMP_BUCKET}/."
    return 1
  fi

  local selected_url="" selected_client="" selected_time=""
  local url client ts

  # Direct import by client name: take that client's most recent dump.
  if [[ -n "${client_name}" ]]; then
    while IFS=$'\t' read -r url client ts; do
      if [[ "${client:l}" == "${client_name:l}" ]]; then
        selected_url="${url}"
        selected_client="${client}"
        selected_time="${ts}"
        break
      fi
    done <<<"${options_text}"

    if [[ -z "${selected_url}" ]]; then
      _sc_error "Client '${client_name}' not found in available dumps."
      _sc_info "Available: $(printf '%s\n' "${options_text}" | cut -f2 | sort -u | paste -sd', ')"
      return 1
    fi
  else
    if ! command -v fzf >/dev/null 2>&1; then
      _sc_warn "fzf not found; falling back to the default SCT prompt."
      sct henk import "${args[@]}"
      return $?
    fi

    local selection
    selection="$(printf '%s\n' "${options_text}" |
      fzf --prompt='Import cluster > ' --with-nth=2,3 --delimiter=$'\t' \
          --header="Select a customer dump to import" --height=60% --reverse)"
    local pick_status=$?

    if ((pick_status != 0)) || [[ -z "${selection}" ]]; then
      _sc_warn "Cluster import selection cancelled."
      return 130
    fi

    IFS=$'\t' read -r selected_url selected_client selected_time <<<"${selection}"
  fi

  _sc_info "📥 Importing cluster dataset: ${selected_client} (${selected_time})"

  _cluster_import_run "${selected_url}" "${args[@]}"
  local exit_code=$?

  if ((exit_code == 0)); then
    _sc_success "Cluster import complete."
    return 0
  fi

  _sc_error "Cluster import failed."
  return ${exit_code}
}
