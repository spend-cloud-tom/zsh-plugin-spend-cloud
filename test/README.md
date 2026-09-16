# Regression tests

Guards the `cluster-import` reauthentication bug.

`sct henk import` shells out to `gcloud storage`, and gcloud only runs its
reauthentication challenge when **both stdin and stderr are TTYs**. The old
implementation drove sct's interactive menu by piping a selection number into
it (`printf ... | sct henk import ... 2>&1`), which made that impossible:
the routine "Reauthentication required. Please enter your password:" prompt
became a hard `cannot prompt during non-interactive execution` failure, and
the plugin then reported it as "Unable to parse SCT cluster list."

The stubs in `bin/` stand in for `gcloud` and `sct` and fail if they are handed
a piped stdin/stderr, mirroring the real behaviour.

Run:

    ./test/test_cluster_import.zsh
    ./test/test_fzf_path.zsh

Note: run them with stdout/stderr going to a terminal or a file, **not** a pipe
(`| tee`, `| tail`), or the stubs will correctly refuse just like real gcloud.
