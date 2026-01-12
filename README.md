# SpendCloud Plugin for Zsh

> ✅ **Zsh Plugin Standard Compliant** | 🎨 **Google Shell Style Guide**

A comprehensive oh-my-zsh compatible plugin for SpendCloud and Proactive Frame development workflow.

## 🎉 What's New in v2.0

✅ **Fully compliant with [Zsh Plugin Standard](https://z-shell.github.io/community/zsh_plugin_standard)**
✅ **All 8 module files updated** (including cluster-import.zsh)
✅ **No breaking changes** - same commands, same workflow
✅ **New capability**: Clean unload with `spend_cloud_plugin_unload`
✅ **Better error detection** and handling
✅ **Improved maintainability** with consistent code standards

**For users:** Everything works the same! Keep using it normally.
**For details:** See [COMPLIANCE.md](COMPLIANCE.md), [CHANGES.md](CHANGES.md), and [TEST_RESULTS.md](TEST_RESULTS.md)

## Features## Features



- 🚀 Cluster lifecycle management (`cluster` command)### Aliases

- 📥 Interactive database import with fzf (`cluster-import` command)- **Navigation**: `sc`, `scapi`, `scui`, `pf`

- 🗄️ Database migration management (`migrate` command)  - **VS Code**: `cui`, `capi`, `cpf`

- 🧹 Client cleanup utilities (`nuke` command)- **Quick Start**: `devapi`

- 🔗 Quick navigation aliases

### Functions

## Installation- **`cluster`** - Manage SpendCloud cluster lifecycle and dev services

- **`cluster-import`** - Interactive picker for `sct shell cluster import`

Add `spend-cloud` to your plugins array in `~/.zshrc`:- **`migrate`** - Handle database migrations across multiple groups

- **`nuke`** - Destructive client cleanup tool (requires `ENABLE_NUKE=1`)

```zsh

plugins=(git zsh-autosuggestions ... spend-cloud)## Installation

```

### Automatic Installation (Recommended)

## Structure

This plugin is automatically installed when you run the dotfiles installer:

The plugin is modularized for maintainability:

```bash

```cd ~/projects/dotfiles

.zsh/plugins/spend-cloud/./install.sh

├── spend-cloud.plugin.zsh    # Main entry point (loads all modules)```

└── lib/

    ├── common.zsh            # Shared utilities and constantsThe installer will:

    ├── docker.zsh            # Docker container management1. Copy the plugin to `~/.oh-my-zsh/custom/plugins/spend-cloud/`

    ├── aliases.zsh           # Navigation aliases2. Set up all necessary files and permissions

    ├── cluster.zsh           # Cluster lifecycle command

    ├── cluster-import.zsh    # Cluster import commandAfter installation, simply uncomment `spend-cloud` in your `~/.zshrc` plugins array.

    ├── migrate.zsh           # Database migration command

    └── nuke.zsh              # Client cleanup tool### Manual Installation

```

If you need to install manually, see [INSTALL.md](./INSTALL.md).

## Commands

### Method 1: Via Plugins Array (Recommended)

### `cluster` - Cluster Lifecycle Management

1. Edit `~/.zshrc`

```bash2. Uncomment `spend-cloud` in the plugins array:

cluster                # Start cluster + dev services   ```zsh

cluster --rebuild      # Rebuild and start with fresh images   plugins=(

cluster stop           # Stop all services     git

cluster logs [service] # View logs     zsh-autosuggestions

cluster help           # Show help     # ...

```     spend-cloud  # Uncomment this line

   )

### `cluster-import` - Interactive Database Import   ```

3. Restart your shell or run: `exec zsh`

```bash

cluster-import  # Interactive fzf selection of database dumps### Method 2: Runtime Toggle

```

Enable temporarily without editing `.zshrc`:

Features:```zsh

- 🔍 Fuzzy search through available dumps (if fzf installed)enable-spend-cloud

- 📅 Human-readable timestamps```

- 🎨 Clean, filtered output

- ⚡ Progress indicatorsTo disable (requires shell restart for full unload):

```zsh

### `migrate` - Database Migrationsdisable-spend-cloud

exec zsh

```bash```

migrate              # Run all migrations in default order

migrate debug        # Run each group separately## Usage Examples

migrate group <g1,g2>  # Run custom groups

migrate status       # Show migration status### Cluster Management

migrate tinker       # Open artisan tinker

migrate customers    # Run customers path only```zsh

migrate config       # Run config path only# Start cluster and dev services

migrate shared       # Run sharedStorage path onlycluster

migrate rollback customers  # Rollback customers migrations

migrate help         # Show help# Rebuild with fresh images

```cluster --rebuild



### `nuke` - Client Cleanup (Dangerous)# Stop all services

cluster stop

```bash

export ENABLE_NUKE=1  # Required safety flag# View logs

nuke                  # Interactive client selectioncluster logs

nuke --verify <client>  # Analyze without changescluster logs api

nuke <client>         # Clean up specific client

```# Fuzzy-select database import target (requires fzf)

cluster-import

**Warning**: This is a destructive operation. Use with extreme caution.

# Help

## Aliasescluster help

```

| Alias | Command | Description |

|-------|---------|-------------|### Database Migrations

| `sc` | `cd ~/development/spend-cloud` | Go to SpendCloud root |

| `scapi` | `sc && cd api` | Go to API directory |```zsh

| `scui` | `sc && cd ui` | Go to UI directory |# Run all migration groups

| `cui` | `code ~/development/spend-cloud/ui` | Open UI in VS Code |migrate

| `capi` | `code ~/development/spend-cloud/api` | Open API in VS Code |

| `devapi` | `scapi && sct dev` | Start API dev server |# Run specific group

| `pf` | `cd ~/development/proactive-frame` | Go to Proactive Frame |migrate group customers

| `cpf` | `code ~/development/proactive-frame` | Open PF in VS Code |

# Debug mode (run each group separately)

## Configurationmigrate debug



Environment variables (optional):# Status

migrate status

- `SC_API_DIR` - API directory path (default: `~/development/spend-cloud/api`)

- `SC_PROACTIVE_DIR` - Proactive Frame path (default: `~/development/proactive-frame`)# Rollback

- `SC_DEV_LOG_DIR` - Log directory (default: `~/.cache/spend-cloud/logs`)migrate rollback customers

- `MIGRATION_GROUP_ORDER` - Custom migration group order

- `ENABLE_NUKE` - Required to use `nuke` command (safety)# Help

- `NO_COLOR` - Disable colored outputmigrate help

```

## Dependencies

### Client Cleanup (DANGEROUS)

- **Required**: `docker`, `sct` (SpendCloud CLI)

- **Optional**: `fzf` (for interactive selection in `cluster-import`)⚠️ **Requires `ENABLE_NUKE=1` environment variable**



## Development```zsh

# Enable nuke functionality

The plugin follows shell scripting best practices:export ENABLE_NUKE=1

- Consistent naming conventions (`_sc_*` for private functions)

- Single Responsibility Principle (one file per command)# Analyze what would be deleted (safe)

- Proper error handling and exit codesnuke --verify clientname

- Comprehensive function documentation

- DRY principle (shared utilities in `common.zsh`)# Actually delete (destructive!)

nuke clientname

To add a new command:

1. Create a new file in `lib/`# Interactive selection

2. Add source line to `spend-cloud.plugin.zsh`nuke

3. Document in this README

# Help

## Licensenuke --help

```

Internal SpendCloud tooling.

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `ENABLE_NUKE` | (unset) | Must be set to `1` to allow `nuke` command |
| `MIGRATION_GROUP_ORDER` | `proactive_config,proactive-default,sharedStorage,customers` | Override default migration group order |
| `DB_USERNAME` | `root` | Database username for `nuke` |
| `DB_PASSWORD` | (empty) | Database password for `nuke` |
| `DB_SERVICES_HOST` | `mysql-service` | Database host for `nuke` |
| `NUKE_CONFIG_DB` | `spend-cloud-config` | Config database name for `nuke` |

## Requirements

- Docker
- `sct` (SpendCloud CLI)
- Oh My Zsh
- `fzf` (optional, enables `cluster-import` picker)

## Safety Features

- **Duplicate Load Protection**: Won't reload if already active
- **Nuke Safeguards**:
  - Requires `ENABLE_NUKE=1` environment variable
  - Protected name blacklist
  - Dual confirmation prompts
  - Verify mode for safe analysis
- **Colorized Output**: Clear visual feedback (respects `NO_COLOR`)

## Logs

Development service logs are stored in:
```
~/.cache/spend-cloud/logs/
```

## Troubleshooting

### Plugin Not Loading

1. Check plugin path exists:
   ```zsh
   ls ~/.zsh/plugins/spend-cloud/spend-cloud.plugin.zsh
   ```

2. Verify custom plugin directory is in fpath:
   ```zsh
   echo $fpath | grep "\.zsh/plugins"
   ```

3. Check for syntax errors:
   ```zsh
   zsh -n ~/.zsh/plugins/spend-cloud/spend-cloud.plugin.zsh
   ```

### Commands Not Found

If `cluster`, `migrate`, or `nuke` are not found:
- Ensure plugin is uncommented in plugins array
- Restart shell: `exec zsh`
- Check if loaded: `echo $_SPEND_CLOUD_PLUGIN_LOADED`

### Alias Conflicts

If you experience alias conflicts with other plugins:
- Load `spend-cloud` after other plugins
- Check for conflicts: `alias | grep -E "cluster|migrate|nuke"`

## Contributing

This plugin follows the [Google Shell Style Guide](https://google.github.io/styleguide/shellguide.html) with adaptations for zsh.

See `/.github/copilot-instructions.md` for coding standards.
