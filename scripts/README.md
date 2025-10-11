# Release Script

Automates the entire Git Foil release process.

## Usage

```bash
./scripts/release.sh <version>
```

## Examples

```bash
# Release version 0.7.4
./scripts/release.sh 0.7.4

# Release version 0.8.0
./scripts/release.sh 0.8.0

# Release version 1.0.0
./scripts/release.sh 1.0.0
```

## What It Does

1. Creates Git tag (e.g., v0.7.4)
2. Pushes tag to GitHub
3. Calculates SHA256 for release tarball
4. Updates Homebrew formula
5. Commits and pushes formula update

## Requirements

- Clean working directory (no uncommitted changes)
- SSH access to GitHub
- Write access to both repos:
  - `code-of-kai/git-foil`
  - `code-of-kai/homebrew-gitfoil`

## After Release

Users can upgrade with:
```bash
brew update && brew upgrade git-foil
```
