# Development Guide

## Project Structure

```
git-foil/              # Source code (this directory)
├── lib/                      # Elixir source code
├── native/                   # Rust NIFs
├── _build/dev/rel/git_foil/  # Build output (dev mode)
├── install.sh               # Production installation
└── install-dev.sh           # Development installation (recommended)
```

## Best Practice Workflow

### Initial Setup (One Time)

```bash
# Install in development mode (uses symlinks)
./install-dev.sh
```

This creates symlinks from `/usr/local/` to your `_build` directory, so rebuilds automatically update the installed version.

### Development Cycle

```bash
# 1. Make code changes
# 2. Rebuild
mix release --overwrite

# 3. Test immediately (no reinstall needed!)
git-foil --version
```

### Production Installation

When you want to create a proper production installation (copies files instead of symlinks):

```bash
./install.sh
```

## Installation Locations

- **Source**: `/Users/kaitaylor/Documents/Coding/git-foil`
- **Build**: `/Users/kaitaylor/Documents/Coding/git-foil/_build/dev/rel/git_foil`
- **Install**: `/usr/local/git-foil` (symlink to build in dev mode)
- **Binary**: `/usr/local/bin/git-foil` (symlink to executable)

## Why This Approach?

✅ **No manual copying**: Scripts handle installation
✅ **Fast iteration**: Dev mode uses symlinks - rebuild and test immediately
✅ **Clean separation**: Source, build, and install are clearly separated
✅ **Production ready**: `install.sh` creates proper standalone installation

## Troubleshooting

### "Permission denied" when running install scripts

The scripts use `sudo` for system-wide installation. You'll be prompted for your password.

### Want to install elsewhere?

```bash
INSTALL_PREFIX=$HOME/.local ./install-dev.sh
```

Then add `$HOME/.local/bin` to your PATH.
