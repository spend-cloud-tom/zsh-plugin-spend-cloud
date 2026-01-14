# spend-cloud (Oh My Zsh plugin)

[![Shell](https://img.shields.io/badge/shell-zsh-89e051)](https://www.zsh.org/)
[![Zsh Plugin Standard](https://img.shields.io/badge/Zsh%20Plugin%20Standard-compliant-blue)](https://zsh-plugin-standard.github.io/)

SpendCloud / Proactive Frame developer tooling for Zsh.

This plugin wraps common workflows around the SpendCloud CLI (`sct`) and the local Docker-based cluster: starting/stopping services, importing customer datasets, running migrations (with analysis), and safely cleaning up corrupted client environments.

## Features

- **Project navigation aliases** for SpendCloud + Proactive Frame
- **`cluster`**: start/stop/rebuild the local cluster and dev services
- **`cluster-import`**: import a customer dump (interactive via `fzf` or direct via `--client`), with cleaner output
- **`migrate`**: run grouped Laravel migrations in a safe mode (continues on errors) and optionally analyze missing-table errors via `lib/migration-healer.py`
- **`nuke`**: destructive client cleanup (gated by `ENABLE_NUKE=1`) to remove databases/config rows/files for a client
- **`spend-cloud`**: interactive command hub

## Why it’s useful

- Reduces repetitive “glue” commands across Docker, `sct`, and Laravel artisan
- Makes migration failures easier to understand (and faster to fix)
- Provides a safer, more complete cleanup path when a customer environment is corrupted

## Installation

### Oh My Zsh

1. Clone into your custom plugins directory:

```zsh
git clone https://github.com/spend-cloud-tom/zsh-plugin-spend-cloud \
  ~/.oh-my-zsh/custom/plugins/spend-cloud
```

2. Enable the plugin in `~/.zshrc`:

```zsh
plugins=(... spend-cloud)
```

3. Reload your shell:

```zsh
source ~/.zshrc
```

### Zinit

```zsh
zinit light spend-cloud-tom/zsh-plugin-spend-cloud
```

### Antigen

```zsh
antigen bundle spend-cloud-tom/zsh-plugin-spend-cloud
```

### Manual

```zsh
source /path/to/zsh-plugin-spend-cloud/spend-cloud.plugin.zsh
```

## Requirements

- **Zsh**
- **Docker** (daemon running)
- **SpendCloud CLI**: `sct` (used by `cluster`, `cluster-import`, and some dev workflows)
- **Optional**: `fzf` for interactive selection (falls back to non-fzf mode)
- **Optional**: `python3` for migration analysis output in `migrate`

## Configuration

### Environment variables

- `NO_COLOR=1`: disable colored output

**Migrations**
- `MIGRATION_GROUP_ORDER="proactive_config,proactive-default,sharedStorage,customers"`: override group order

**Nuke (destructive)**
- `ENABLE_NUKE=1` (**required**) to allow `nuke` to run
- `DB_USERNAME` (default: `root`)
- `DB_PASSWORD` (default: empty)
- `DB_SERVICES_HOST` (default: `mysql-service`)
- `NUKE_CONFIG_DB` (default: `spend-cloud-config`)

### Project path aliases

The navigation aliases in `lib/aliases.zsh` assume these directories:

- `~/development/spend-cloud`
- `~/development/proactive-frame`

If your paths differ, edit `lib/aliases.zsh` to match your setup.

## Usage

### Hub (interactive)

```zsh
spend-cloud
```

### Cluster lifecycle

```zsh
cluster
cluster --rebuild
cluster logs
cluster logs api
cluster stop
```

### Import a customer dataset

Interactive (requires `fzf`):

```zsh
cluster-import
```

Direct import:

```zsh
cluster-import --client watermeloen
```

If the target client has “residue” (existing DB/config rows/files), `cluster-import --client ...` will attempt a cleanup via `nuke --force` **if** `nuke` is available and `ENABLE_NUKE=1` is set.

### Run migrations

Safe mode (default behavior):

```zsh
migrate
```

Other modes:

```zsh
migrate debug
migrate heal
migrate check sherpa
migrate group proactive_config,customers
migrate rollback customers
```

If `python3` is available, `migrate` will run `lib/migration-healer.py` to summarize missing-table errors and suggest next steps.

### Nuke a client (destructive)

`nuke` is intentionally gated:

```zsh
export ENABLE_NUKE=1
nuke --verify watermeloen
nuke watermeloen
nuke --force watermeloen
```

What it deletes (when present):

- Customer database(s) matching the client
- Config DB rows in `00_settings` and module settings tables (`01_settings` … `08_settings`)
- Client registry row (`client`)
- `/data/<client>` folder in the cluster

## Contributing

- Keep changes small and focused.
- Preserve the public API described in `spend-cloud.plugin.zsh` (aliases + `cluster`, `cluster-import`, `migrate`, `nuke`, `spend-cloud`).
- Prefer safe defaults and explicit opt-ins for destructive behavior.
- Maintain Zsh Plugin Standard compatibility.

## License

No license file is currently included in this repository. Treat it as **proprietary/internal** until a `LICENSE` is added.

## Maintainers

- @spend-cloud-tom

## Links

- Plugin entrypoint: `spend-cloud.plugin.zsh`
- Commands: `lib/cluster.zsh`, `lib/cluster-import.zsh`, `lib/migrate.zsh`, `lib/nuke.zsh`, `lib/hub.zsh`
- Migration analyzer script: `lib/migration-healer.py`
- Issues: [GitHub Issues](../../issues)
