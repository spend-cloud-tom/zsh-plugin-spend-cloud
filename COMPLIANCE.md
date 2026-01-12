# Zsh Plugin Standard Compliance

This plugin follows the [Zsh Plugin Standard](https://z-shell.github.io/community/zsh_plugin_standard) and Google Shell Style Guide.

## Compliance Checklist

### ✅ Implemented Standards

#### 1. Standardized `$0` Handling (Section 1)
```zsh
0="${ZERO:-${${0:#$ZSH_ARGZERO}:-${(%):-%N}}}"
0="${${(M)0:#/*}:-$PWD/$0}"
typeset -gr SPEND_CLOUD_PLUGIN_DIR="${0:h}"
```

**Benefits:**
- Works with `eval "$(<plugin)"` loading
- Handles `setopt no_function_argzero` and `setopt posix_argzero`
- Compatible with all plugin managers

#### 2. Functions Directory Support (Section 2)
```zsh
if [[ ${zsh_loaded_plugins[-1]} != */spend-cloud && -z ${fpath[(r)${SPEND_CLOUD_PLUGIN_DIR}/functions]} ]]; then
  if [[ -d "${SPEND_CLOUD_PLUGIN_DIR}/functions" ]]; then
    fpath=("${SPEND_CLOUD_PLUGIN_DIR}/functions" "${fpath[@]}")
  fi
fi
```

**Note:** Currently, all functions are in `lib/` subdirectory. Can be migrated to `functions/` for autoloading.

#### 4. Unload Function (Section 4)
```zsh
spend_cloud_plugin_unload()
```

**Features:**
- Removes all aliases: `sc`, `scapi`, `scui`, `cui`, `capi`, `devapi`, `pf`, `cpf`
- Removes all functions: public commands and internal helpers
- Cleans up `$fpath` entries
- Unsets all global variables

**Usage:**
```zsh
# Unload the plugin
spend_cloud_plugin_unload
```

#### 7. Plugin Manager Activity Indicator (Section 7)
```zsh
typeset -ga zsh_loaded_plugins
zsh_loaded_plugins+=("${SPEND_CLOUD_PLUGIN_DIR}")
```

**Allows:**
- Detection of plugin manager presence
- Checking which plugins are loaded
- Conditional behavior based on loading context

### 📋 Best Practices Implemented

#### Standard Recommended Options
Every function uses:
```zsh
emulate -L zsh ${=${options[xtrace]:#off}:+-o xtrace}
setopt extended_glob warn_create_global typeset_silent no_short_loops rc_quotes no_auto_pushd
```

**Benefits:**
- `extended_glob`: Advanced pattern matching
- `warn_create_global`: Catches typos and missing localizations
- `typeset_silent`: Allows variable redeclaration in loops
- `no_short_loops`: Better error detection
- `rc_quotes`: Easy apostrophe insertion in strings
- `no_auto_pushd`: Prevents directory stack pollution

#### Standard Recommended Variables
Every function localizes:
```zsh
local MATCH REPLY
integer MBEGIN MEND
local -a match mbegin mend reply
```

**Prevents:**
- Variable leakage to global scope
- Conflicts with glob substitutions
- Unexpected side effects from regex/pattern matching

#### Parameter Naming Convention
- **Uppercase globals**: `SC_DEV_CONTAINER_PATTERN`, `C_RED`, etc.
- **Lowercase locals**: `container`, `service_dir`, etc.
- **Prefixed internals**: `_sc_*`, `_cluster_*`, `_migrate_*`, `_nuke_*`

#### Proper Quoting
All variable expansions are quoted:
```zsh
docker ps --format '{{.Names}}' | grep -E "${SC_DEV_CONTAINER_PATTERN}"
```

### ⚠️ Not Yet Implemented (Optional)

#### 3. Binaries Directory (Section 3)
Not needed - this plugin provides shell functions only.

#### 5. `@zsh-plugin-run-on-unload` Call (Section 5)
Not needed - unload function handles all cleanup.

#### 6. `@zsh-plugin-run-on-update` Call (Section 6)
Could be added if update hooks are needed in the future.

#### 8. Global `$ZPFX` Parameter (Section 8)
Not applicable - no binary compilation needed.

#### 9. `$PMSPEC` Capabilities Parameter (Section 9)
Could be implemented by plugin managers.

### 🎨 Style Guide Compliance

#### Google Shell Style Guide
- ✅ Proper function headers with documentation
- ✅ Consistent 2-space indentation
- ✅ Safe quoting throughout
- ✅ Meaningful variable names
- ✅ Error handling with proper exit codes
- ✅ No global variable pollution

#### Function Naming Prefixes
While the Zsh Plugin Standard recommends special prefixes (`.`, `→`, `+`, `/`, `@`), this plugin uses:
- `_sc_*` for private utilities
- `_cluster_*`, `_migrate_*`, `_nuke_*` for internal module functions
- `cluster`, `cluster-import`, `migrate`, `nuke` for public API

**Rationale:** Simpler for tab completion, more portable across systems.

## Testing Compliance

### Load/Unload Test
```zsh
# Load plugin
source ~/.zsh/plugins/spend-cloud/spend-cloud.plugin.zsh

# Verify loaded
type cluster
type _sc_print

# Unload
spend_cloud_plugin_unload

# Verify unloaded
type cluster 2>&1 | grep "not found"
```

### Variable Isolation Test
```zsh
# Before loading
echo ${SPEND_CLOUD_PLUGIN_DIR:-UNSET}  # Should be UNSET

# Load plugin
source ~/.zsh/plugins/spend-cloud/spend-cloud.plugin.zsh

# Check variable
echo ${SPEND_CLOUD_PLUGIN_DIR}  # Should show path

# Unload
spend_cloud_plugin_unload

# Verify cleanup
echo ${SPEND_CLOUD_PLUGIN_DIR:-UNSET}  # Should be UNSET again
```

## Migration Notes

### For Users
No changes needed - all existing functionality works identically.

### For Developers
- All functions now use proper emulation and option settings
- Standard variables are localized in every function
- Plugin can be cleanly unloaded and reloaded
- Compatible with more plugin managers

## References

- [Zsh Plugin Standard](https://z-shell.github.io/community/zsh_plugin_standard)
- [Google Shell Style Guide](https://google.github.io/styleguide/shellguide.html)
- [Zsh Manual - Functions](https://zsh.sourceforge.io/Doc/Release/Functions.html)
