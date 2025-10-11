# Git Foil Release Scripts

Automation scripts for releasing new versions of Git Foil.

## Release Script

The `release.sh` script automates the entire release process from start to finish.

### What It Does

1. ✅ Validates your repository state (clean working directory, correct branch)
2. ✅ Creates a Git tag for the new version
3. ✅ Pushes the tag to GitHub
4. ✅ Calculates the SHA256 checksum for the release tarball
5. ✅ Clones/updates the Homebrew formula repository
6. ✅ Updates the formula with the new version and checksum
7. ✅ Commits and pushes the formula update
8. ✅ Provides a summary with instructions for users

### Usage

```bash
# Make sure you're in the git-foil repository root
cd /path/to/git-foil

# Run the release script with the new version number
./scripts/release.sh 0.7.4
```

### Example Output

When you run `./scripts/release.sh 0.7.4`, you'll see:
- Step-by-step progress with checkmarks
- Validation of your repository state
- Automatic tag creation and push
- SHA256 calculation
- Formula update and push
- Final summary with user upgrade instructions

### Requirements

- Git with SSH access to GitHub (for pushing)
- `curl` and `shasum` commands available
- Write access to both repositories:
  - `code-of-kai/git-foil`
  - `code-of-kai/homebrew-gitfoil`

### Error Handling

The script will exit with an error if:
- You have uncommitted changes
- The tag already exists
- Can't download the release tarball
- Can't access the Homebrew formula repository

## Future Enhancements

Potential improvements:
- [ ] Automatically generate release notes from git commits
- [ ] Create GitHub Release via API
- [ ] Run tests before releasing
- [ ] Bump version in `mix.exs` automatically
