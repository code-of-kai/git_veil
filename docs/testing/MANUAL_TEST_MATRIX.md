# GitFoil Manual Test Matrix
## Complete Decision Fork Test Coverage

This document maps every user choice, decision fork, and execution path in git-foil commands for comprehensive manual testing.

---

## 1. `git-foil init`

### Decision Fork 1.1: Repository State
- **Path A**: Not a Git repository
  - Prompt: "Would you like to create one? [Y/n]"
    - **A1**: `Y` or `Enter` → Creates git repo, continues
    - **A2**: `y` → Creates git repo, continues
    - **A3**: `n` → Exits with message
    - **A4**: `N` → Exits with message
    - **A5**: Any other input → Treats as "no", exits

### Decision Fork 1.2: Existing Key State
- **Path B**: GitFoil already initialized
  - Shows message with key location and patterns count
  - Exits (unless --force used)

- **Path C**: GitFoil already initialized with --force flag
  - Prompt: "Choose option (1, 2, or 3):"
    - **C1**: `1` → Use existing key
    - **C2**: `2` → Create new key (backs up old key)
    - **C3**: `3` → Exit
    - **C4**: Any other → Error message

### Decision Fork 1.3: Initialization Confirmation
- Prompt: "Proceed with initialization? [Y/n]:"
  - **Path D1**: `Y` or `Enter` → Continues
  - **Path D2**: `y` → Continues
  - **Path D3**: `n` or `N` → Exits with "Cancelled" message
  - **Path D4**: Any other → Treats as "no", exits

### Decision Fork 1.4: Pattern Configuration (unless --skip-patterns)
- Prompt: "Which files should be encrypted? Choice [1]:"
  - **Path E1**: `Enter` (default) → Everything pattern
  - **Path E2**: `1` → Everything pattern
  - **Path E3**: `2` → Secrets only pattern
  - **Path E4**: `3` → Environment files pattern
  - **Path E5**: `4` → Custom patterns (interactive)
  - **Path E6**: `5` → Decide later (skip)
  - **Path E7**: Any other → Error, re-prompts

### Decision Fork 1.5: Custom Patterns (if E5 chosen)
- Loop: "Pattern: " (blank to finish)
  - **Path F1**: Enter pattern → Adds pattern, continues loop
  - **Path F2**: Blank line → Exits custom pattern mode
  - **Path F3**: Invalid pattern → Error, re-prompts

### Decision Fork 1.6: Encrypt Existing Files
- Prompt: "Encrypt now? [Y/n]:"
  - **Path G1**: `Y` or `Enter` → Encrypts matching files
  - **Path G2**: `y` → Encrypts matching files
  - **Path G3**: `n` or `N` → Skips encryption
  - **Path G4**: Any other → Treats as "no", skips

### Flags for init
- `--force` or `-f`: Overwrite existing key
- `--skip-patterns`: Skip pattern configuration
- `--verbose` or `-v`: Show verbose output

---

## 2. `git-foil configure`

### Decision Fork 2.1: Pattern Selection
- Prompt: "Which files should be encrypted? Choice [1]:"
  - **Path H1**: `Enter` → Everything
  - **Path H2**: `1` → Everything
  - **Path H3**: `2` → Secrets only
  - **Path H4**: `3` → Environment files
  - **Path H5**: `4` → Custom patterns (interactive)
  - **Path H6**: `5` → Exit
  - **Path H7**: Any other → Error

### Decision Fork 2.2: Custom Patterns (if H5 chosen)
- Same as Decision Fork 1.5 (F1-F3)

---

## 3. `git-foil unencrypt`

### Decision Fork 3.1: Initial Warning
- Prompt: "Do you want to continue and permanently remove encryption? [y/N]:"
  - **Path I1**: `y` → Continues to confirmation
  - **Path I2**: `yes` → Continues to confirmation
  - **Path I3**: `N` or `Enter` → Exits with helpful message
  - **Path I4**: `n` → Exits with helpful message
  - **Path I5**: Any other → Treats as "no", exits

### Decision Fork 3.2: Final Confirmation (if I1 or I2)
- Prompt: "Are you absolutely sure? Type 'yes' to proceed:"
  - **Path J1**: `yes` → Proceeds with unencryption
  - **Path J2**: Anything else → Cancels, exits

### Flags for unencrypt
- `--keep-key`: Preserve master encryption key (don't delete)

---

## 4. `git-foil encrypt`

### Decision Fork 4.1: No Patterns Configured
- Prompt: "Configure patterns? [Y/n]:"
  - **Path K1**: `Y` or `Enter` → Opens pattern configuration
  - **Path K2**: `y` → Opens pattern configuration
  - **Path K3**: `n` or `N` → Exits
  - **Path K4**: Any other → Treats as "no", exits

### Decision Fork 4.2: Pattern Configuration (if K1 or K2)
- Same as Decision Fork 2.1 (H1-H7)

### Decision Fork 4.3: Encryption Options
- Prompt: "Choose option (1 or 2) [1]:"
  - **Path L1**: `Enter` → Encrypt and stage
  - **Path L2**: `1` → Encrypt and stage
  - **Path L3**: `2` → Encrypt only (don't stage)
  - **Path L4**: Any other → Error

---

## 5. `git-foil rekey`

### Decision Fork 5.1: Rekey Options
- Prompt: "Choose option (1 or 2) [1]:"
  - **Path M1**: `Enter` → Rekey and stage
  - **Path M2**: `1` → Rekey and stage
  - **Path M3**: `2` → Rekey only (don't stage)
  - **Path M4**: Any other → Error

---

## 6. `git-foil commit`

### No interactive prompts
- Stages .gitattributes and commits
- Takes optional message: `git-foil commit -m "message"`
- **Path N1**: With -m flag → Uses provided message
- **Path N2**: Without -m flag → Uses default message

---

## 7. `git-foil add-pattern <pattern>`

### No interactive prompts
- Adds pattern directly
- **Path O1**: Valid pattern → Adds successfully
- **Path O2**: Invalid pattern → Error message
- **Path O3**: No pattern argument → Error

---

## 8. `git-foil remove-pattern <pattern>`

### No interactive prompts
- Removes pattern directly
- **Path P1**: Existing pattern → Removes successfully
- **Path P2**: Non-existent pattern → Error message
- **Path P3**: No pattern argument → Error

---

## 9. `git-foil list-patterns`

### No interactive prompts
- Lists all patterns
- **Path Q1**: Patterns exist → Shows list
- **Path Q2**: No patterns → Shows "none configured"

---

## 10. `git-foil version`

### No interactive prompts
- Shows version
- **Path T1**: Shows version number

---

## 11. `git-foil help`

### No interactive prompts
- **Path V1**: `git-foil help` → Shows general help
- **Path V2**: `git-foil help patterns` → Shows pattern syntax help
- **Path V3**: `git-foil --help` → Shows general help
- **Path V4**: `git-foil -h` → Shows general help

---

## Test Matrix Summary

### Total Decision Forks: 11
### Total Test Paths: 57

### Commands Requiring Manual Testing:
1. ✅ **init** - 18 paths (Forks 1.1-1.6)
2. ✅ **configure** - 8 paths (Forks 2.1-2.2)
3. ✅ **unencrypt** - 5 paths (Forks 3.1-3.2)
4. ✅ **encrypt** - 8 paths (Forks 4.1-4.3)
5. ✅ **rekey** - 4 paths (Fork 5.1)
6. ✅ **commit** - 2 paths (No forks)
7. ✅ **add-pattern** - 3 paths (No forks)
8. ✅ **remove-pattern** - 3 paths (No forks)
9. ✅ **list-patterns** - 2 paths (No forks)
10. ✅ **version** - 1 path (No forks)
11. ✅ **help** - 4 paths (No forks)

### Advanced Commands (see ADVANCED.md):
- **clean** - Git filter (internal)
- **smudge** - Git filter (internal)

---

## Testing Methodology

### For Each Path:
1. **Setup**: Create test conditions
2. **Execute**: Run command with specific input
3. **Verify**: Check expected outcome
4. **Cleanup**: Reset for next test

### Test Execution Template:

```bash
# Test ID: [Command]-[Fork]-[Path]
# Description: [What this tests]
# Setup: [Prerequisites]
# Input: [User choices]
# Expected: [Expected result]
# Actual: [Record actual result]
# Status: PASS/FAIL
```

### Example:

```bash
# Test ID: init-1.1-A1
# Description: Init in non-git directory, user chooses to create repo
# Setup: mkdir test && cd test (no git repo)
# Input: git-foil init → Y
# Expected: Creates .git directory, continues with init
# Actual: [Record result]
# Status: PASS/FAIL
```

---

## Edge Cases to Test

### Input Variations:
- ✅ Empty input (just Enter)
- ✅ Lowercase vs uppercase
- ✅ Whitespace before/after input
- ✅ Invalid input
- ✅ EOF (Ctrl-D)
- ✅ Interrupted input (Ctrl-C)

### State Variations:
- ✅ Fresh repository
- ✅ Existing encryption
- ✅ Corrupted state
- ✅ Missing files
- ✅ Permission errors

### Pattern Variations:
- ✅ Valid glob patterns
- ✅ Invalid patterns
- ✅ Overlapping patterns
- ✅ Exclusion patterns
- ✅ Unicode in patterns

---

## Automation Hints

While this is for manual testing, consider scripting:
```bash
# Automated input feeding
echo -e "Y\n1\nY" | git-foil init

# Or use expect for complex flows
expect -c 'spawn git-foil init; expect "Proceed"; send "Y\r"; expect eof'
```
