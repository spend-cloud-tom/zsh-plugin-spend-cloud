#!/usr/bin/env zsh
# Regression test: cluster-import must never hand gcloud/sct a piped stdin or
# stderr, because that makes gcloud's reauth challenge impossible
# ("Reauthentication failed. cannot prompt during non-interactive execution").

TEST_DIR="${0:A:h}"
export SCT_LOG="${TEST_DIR}/sct.log"
: > "$SCT_LOG"
export PATH="${TEST_DIR}/bin:$PATH"

typeset -g fail_count=0
ok()   { print -r -- "  ✅ $1" }
fail() { print -r -- "  ❌ $1"; ((fail_count++)) }

# Stub out cluster/docker bits cluster-import touches so we test only the auth path.
docker() {
  case "$1" in
    ps) print -r -- "mysql-service\nproactive-config\nspend-cloud-api" ;;
    exec) return 0 ;;
    *) return 0 ;;
  esac
}
fzf() { head -1 }   # non-interactive: always pick the first entry

source /home/tom/projects/zsh-plugin-spend-cloud/lib/common.zsh
source /home/tom/projects/zsh-plugin-spend-cloud/lib/cluster.zsh
source /home/tom/projects/zsh-plugin-spend-cloud/lib/cluster-import.zsh

print -r -- "TEST 1: --client import succeeds when gcloud requires a real (non-pipe) stdin/stderr"
# Redirect to FILES, not pipes: a pipe on stderr is exactly the condition
# that breaks gcloud's reauth prompt, so the harness must not create it.
cluster-import --client acme >"${TEST_DIR}/out.txt" 2>"${TEST_DIR}/err.txt" </dev/null
rc=$?
out="$(cat "${TEST_DIR}/out.txt" "${TEST_DIR}/err.txt")"
if (( rc == 0 )); then ok "exit 0"; else fail "exit $rc; output:\n$out"; fi

print -r -- "TEST 2: sct was never given a piped stdin"
if grep -q "STDIN: pipe" "$SCT_LOG"; then
  fail "sct received a piped stdin:\n$(cat "$SCT_LOG")"
else
  ok "sct stdin was not a pipe"
fi

print -r -- "TEST 3: sct was invoked with the gs:// URL directly"
if grep -q "ARGV: henk import gs://henk-db-dumps/acme" "$SCT_LOG"; then
  ok "sct henk import <url>"
else
  fail "unexpected sct invocation:\n$(cat "$SCT_LOG")"
fi

print -r -- "TEST 4: no 'Unable to parse SCT cluster list' masking of an auth error"
if print -r -- "$out" | grep -q "Unable to parse SCT cluster list"; then
  fail "auth failure was masked as a parse error"
else
  ok "no parse-error masking"
fi

print -r -- ""
if (( fail_count == 0 )); then print -r -- "ALL PASS"; else print -r -- "$fail_count FAILURE(S)"; exit 1; fi
