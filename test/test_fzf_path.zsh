#!/usr/bin/env zsh
TEST_DIR="${0:A:h}"
export SCT_LOG="${TEST_DIR}/sct2.log"; : > "$SCT_LOG"
export PATH="${TEST_DIR}/bin:$PATH"
docker() { case "$1" in ps) print -r -- "mysql-service\nproactive-config";; *) return 0;; esac }
fzf() { head -1 }
source /home/tom/projects/zsh-plugin-spend-cloud/lib/common.zsh
source /home/tom/projects/zsh-plugin-spend-cloud/lib/cluster.zsh
source /home/tom/projects/zsh-plugin-spend-cloud/lib/cluster-import.zsh

print -r -- "TEST 5: interactive (fzf) path picks newest dump and passes the URL"
cluster-import >"${TEST_DIR}/o2.txt" 2>"${TEST_DIR}/e2.txt" </dev/null
rc=$?
print -r -- "  rc=$rc"
cat "${TEST_DIR}/o2.txt"
if grep -q "ARGV: henk import gs://henk-db-dumps/acme_2026-09-15T10:00:00.zip" "$SCT_LOG" && grep -q "STDIN: not-pipe" "$SCT_LOG"; then
  print -r -- "  ✅ newest dump (acme) selected, URL passed, stdin clean"
else
  print -r -- "  ❌ $(cat "$SCT_LOG")"; exit 1
fi

print -r -- ""
print -r -- "TEST 6: sorting - newest first, relative times rendered"
listing="$(_cluster_import_list_dumps)"
_cluster_import_format_dumps "$listing" | cat -A | sed 's/\$$//' | head
