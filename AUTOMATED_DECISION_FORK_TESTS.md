# Automated Decision Fork Test Suite

This document describes the comprehensive automated test suite covering all 57 decision paths documented in `MANUAL_TEST_MATRIX.md`.

## Test Files Created

### 1. `test/support/test_mocks.ex`
**Purpose:** Shared mock implementations for testing

Contains:
- **MockGit** - Implements `GitFoil.Ports.Repository` behavior
- **MockTerminal** - Mock terminal for testing interactive prompts

**Usage:** Used across all decision fork tests to simulate Git operations and user input without actual file system changes or user interaction.

### 2. `test/git_foil/commands/init_decision_forks_test.exs`
**Purpose:** Comprehensive tests for `git-foil init` command

**Coverage: 27 tests covering 18 decision paths**

#### Decision Forks Tested:

**Fork 1.1: Repository State (5 paths)**
- Path A1: User enters 'Y' to create repo
- Path A2: User enters 'y' (lowercase) to create repo
- Path A3: User enters 'n' to decline creating repo
- Path A4: User enters 'N' (uppercase) to decline
- Path A5: User enters invalid input (treated as 'no')

**Fork 1.2: Existing Key with --force flag (4 paths)**
- Path C1: User chooses '1' to use existing key
- Path C2: User chooses '2' to create new key (backs up old)
- Path C3: User chooses '3' to exit
- Path C4: User enters invalid choice

**Fork 1.3: Initialization Confirmation (4 paths)**
- Path D1: User enters 'Y' to proceed
- Path D2: User enters 'y' (lowercase) to proceed
- Path D3: User enters 'n' to cancel
- Path D4: User enters invalid input (treated as 'no')

**Fork 1.4: Pattern Configuration (7 paths)**
- Path E1: User presses Enter (default - Everything)
- Path E2: User chooses '1' - Everything pattern
- Path E3: User chooses '2' - Secrets only pattern
- Path E4: User chooses '3' - Environment files pattern
- Path E5: User chooses '4' - Custom patterns (interactive)
- Path E6: User chooses '5' - Decide later (skip)
- Path E7: User enters invalid choice

**Fork 1.5: Custom Patterns Loop (3 paths)**
- Path F1: User enters pattern, adds it, continues loop
- Path F2: User enters blank line, exits custom pattern mode
- Path F3: User enters invalid pattern (error and re-prompt)

**Fork 1.6: Encrypt Existing Files (4 paths)**
- Path G1: User enters 'Y' to encrypt matching files
- Path G2: User enters 'y' (lowercase) to encrypt
- Path G3: User enters 'n' to skip encryption
- Path G4: User enters invalid input (treated as 'no')

### 3. `test/git_foil/commands/interactive_decision_forks_test.exs`
**Purpose:** Tests for interactive commands (configure, encrypt, rekey, unencrypt)

**Coverage: 25 tests covering 25 decision paths**

#### Decision Forks Tested:

**Configure Command (8 paths - Forks 2.1 & 2.2)**
- Path H1: User presses Enter (default)
- Path H2: User chooses '1' - Everything
- Path H3: User chooses '2' - Secrets only
- Path H4: User chooses '3' - Environment files
- Path H5: User chooses '4' - Custom patterns (interactive)
- Path H6: User chooses '5' - Exit
- Path H7: User enters invalid choice
- Fork 2.2: Custom patterns - blank line exits

**Unencrypt Command (5 paths - Forks 3.1 & 3.2)**
- Path I1: User enters 'y' at first prompt
- Path I2: User enters 'yes' at first prompt
- Path I3: User enters 'N' (default) - exits
- Path I4: User enters 'n' - exits
- Path I5: User enters invalid input - treated as 'no'
- Path J1: User types 'yes' at final confirmation
- Path J2: User types anything else - cancels

**Encrypt Command (8 paths - Forks 4.1 & 4.3)**
- Path K1: User enters 'Y' to configure patterns
- Path K2: User enters 'y' (lowercase)
- Path K3: User enters 'n' - exits
- Path K4: User enters 'N' (uppercase) - exits
- Path L1: User presses Enter - Encrypt and stage (default)
- Path L2: User enters '1' - Encrypt and stage
- Path L3: User enters '2' - Encrypt only (don't stage)
- Path L4: User enters invalid choice - Error

**Re-Encrypt Command (4 paths - Fork 5.1)**
- Path M1: User presses Enter - Re-encrypt and stage (default)
- Path M2: User enters '1' - Re-encrypt and stage
- Path M3: User enters '2' - Re-encrypt only (don't stage)
- Path M4: User enters invalid choice - Error

### 4. `test/git_foil/commands/non_interactive_decision_forks_test.exs`
**Purpose:** Tests for non-interactive commands

**Coverage: 15 tests covering 14 decision paths**

#### Decision Forks Tested:

**Commit Command (2 paths - Fork 6)**
- Path N1: With -m flag - uses provided message
- Path N2: Without -m flag - uses default message

**Add-Pattern Command (3 paths - Fork 7)**
- Path O1: Valid pattern - adds successfully
- Path O2: Invalid pattern - error message
- Path O3: No pattern argument via CLI - error

**Remove-Pattern Command (3 paths - Fork 8)**
- Path P1: Existing pattern - removes successfully
- Path P2: Non-existent pattern - error message
- Path P3: No pattern argument via CLI - error

**List-Patterns Command (2 paths - Fork 9)**
- Path Q1: Patterns exist - shows list
- Path Q2: No patterns - shows 'none configured'

**Version Command (1 path - Fork 13)**
- Path U1: Shows version number

**Help Command (4 paths - Fork 14)**
- Path V1: 'git-foil help' - shows general help
- Path V2: 'git-foil help patterns' - shows pattern syntax help
- Path V3: 'git-foil --help' - shows general help
- Path V4: 'git-foil -h' - shows general help

**Plus 2 edge cases:**
- Unknown command returns error
- Empty command shows help

---

## Running the Tests

### Run All Decision Fork Tests
```bash
cd /path/to/git-foil

# Run all decision fork tests
mix test test/git_foil/commands/*_decision_forks_test.exs

# Run with coverage
mix test test/git_foil/commands/*_decision_forks_test.exs --cover

# Run in trace mode (shows each test as it runs)
mix test test/git_foil/commands/*_decision_forks_test.exs --trace
```

### Run Individual Test Files
```bash
# Init command tests (18 paths)
mix test test/git_foil/commands/init_decision_forks_test.exs

# Interactive commands tests (25 paths)
mix test test/git_foil/commands/interactive_decision_forks_test.exs

# Non-interactive commands tests (14 paths)
mix test test/git_foil/commands/non_interactive_decision_forks_test.exs
```

### Run Specific Test
```bash
# Run a single test by line number
mix test test/git_foil/commands/init_decision_forks_test.exs:42

# Run tests matching a pattern
mix test --only pattern:"Repository State"
```

---

## Test Architecture

### Mock Strategy

Tests use **stateful mocks** via the process dictionary:

```elixir
# Configure mock behavior
MockGit.configure(
  verify_repository: fn -> {:error, "not a git repository"} end,
  init_repository: fn -> {:ok, "Initialized"} end
)

# Configure user inputs (consumed sequentially)
MockTerminal.configure(
  inputs: ["y", "1", "y"]  # User presses: y, then 1, then y
)
```

### Test Isolation

Each test:
1. **Setup:** Cleans `.gitattributes` and `.git/git_foil`
2. **Execute:** Runs command with mocked dependencies
3. **Assert:** Verifies expected outcome
4. **Cleanup:** Removes test files and clears process dictionary

### Integration vs Unit

These are **integration tests** that:
- ✅ Test complete user flows
- ✅ Test decision trees end-to-end
- ✅ Verify interactive prompts work correctly
- ❌ Are slower than unit tests (expect 1-2 seconds per test)
- ❌ May create actual files during testing

---

## Coverage Summary

| Command | Decision Forks | Test Paths | Test File |
|---------|---------------|------------|-----------|
| init | 6 | 18 | `init_decision_forks_test.exs` |
| configure | 2 | 8 | `interactive_decision_forks_test.exs` |
| unencrypt | 2 | 5 | `interactive_decision_forks_test.exs` |
| encrypt | 2 | 8 | `interactive_decision_forks_test.exs` |
| rekey | 1 | 4 | `interactive_decision_forks_test.exs` |
| commit | 0 | 2 | `non_interactive_decision_forks_test.exs` |
| add-pattern | 0 | 3 | `non_interactive_decision_forks_test.exs` |
| remove-pattern | 0 | 3 | `non_interactive_decision_forks_test.exs` |
| list-patterns | 0 | 2 | `non_interactive_decision_forks_test.exs` |
| version | 0 | 1 | `non_interactive_decision_forks_test.exs` |
| help | 0 | 4 | `non_interactive_decision_forks_test.exs` |
| **TOTAL** | **11** | **57** | **3 files** |

Plus 2 additional edge case tests = **59 total tests**

---

## Relationship to MANUAL_TEST_MATRIX.md

These automated tests directly correspond to the manual test paths documented in `MANUAL_TEST_MATRIX.md`:

- **Manual matrix:** Documents all decision forks for human testing
- **Automated tests:** Programmatically test the same decision paths
- **Test names:** Include path IDs (A1, H3, M2, etc.) for easy cross-reference

Example:
```markdown
# MANUAL_TEST_MATRIX.md
Path A1: User enters 'Y' to create repo

# Test file
test "Path A1: User enters 'Y' to create repo" do
  # Automated version of manual test path A1
end
```

---

## Future Enhancements

### Potential Improvements:
1. **Faster mocks** - Replace file I/O with in-memory mocks
2. **Parallel execution** - Run tests concurrently (currently `async: false`)
3. **Property-based testing** - Use StreamData for fuzz testing inputs
4. **Clean/Smudge tests** - Add tests for Git filter commands
5. **Error injection** - Test failure modes (disk full, permissions, etc.)

### Additional Test Scenarios:
- Unicode in filenames and patterns
- Very long file paths (>256 chars)
- Symlinks and special files
- Concurrent git operations
- Large repositories (1000+ files)

---

## Maintenance

### When Adding New Commands:
1. Document decision forks in `MANUAL_TEST_MATRIX.md`
2. Create tests in appropriate `*_decision_forks_test.exs` file
3. Use `MockGit` and `MockTerminal` for dependencies
4. Follow naming convention: `"Path XN: Description"`
5. Update this document with new test counts

### When Modifying Existing Commands:
1. Update `MANUAL_TEST_MATRIX.md` first
2. Update or add tests to match new decision forks
3. Ensure test names still match path IDs
4. Run full test suite to catch regressions

---

## Test Output Example

```bash
$ mix test test/git_foil/commands/init_decision_forks_test.exs

Compiling 3 files (.ex)
Generated git_foil app
...........................

Finished in 45.2 seconds (0.00s async, 45.2s sync)
27 tests, 0 failures

Randomized with seed 123456
```

---

## References

- **MANUAL_TEST_MATRIX.md** - Complete manual test documentation
- **COMMAND_DECISION_TREE.md** - Command overview and decision trees
- **test/git_foil/commands/init_test.exs** - Original init tests (pattern source)
- **test/support/test_mocks.ex** - Shared mock implementations
