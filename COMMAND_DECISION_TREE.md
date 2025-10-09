# GitFoil Command Decision Tree
## Quick Reference for User-Facing Commands

---

## Commands Overview

### ✅ Implemented & User-Facing
| Command | Interactive? | Decision Forks | Status |
|---------|-------------|----------------|--------|
| `init` | Yes | 6 | ✅ Complete |
| `configure` | Yes | 2 | ✅ Complete |
| `unencrypt` | Yes | 2 | ✅ Complete |
| `encrypt` | Yes | 3 | ✅ Complete |
| `rekey` | Yes | 1 | ✅ Complete |
| `commit` | No | 0 | ✅ Complete |
| `add-pattern` | No | 0 | ✅ Complete |
| `remove-pattern` | No | 0 | ✅ Complete |
| `list-patterns` | No | 0 | ✅ Complete |
| `version` | No | 0 | ✅ Complete |
| `help` | No | 0 | ✅ Complete |


### 🔧 Internal Only (Don't Expose to Users)
| Command | Purpose | Should Expose? |
|---------|---------|---------------|
| `clean <file>` | Git filter hook | ⚠️ Advanced users only |
| `smudge <file>` | Git filter hook | ⚠️ Advanced users only |

---

## Decision Tree by Command

### 1. `git-foil init` [6 forks, 18 paths]

```
init
├─ Is Git repo?
│  ├─ NO → "Create one? [Y/n]"
│  │  ├─ Y/y/Enter → Create repo → Continue
│  │  └─ N/n/other → Exit
│  └─ YES → Continue
│
├─ GitFoil exists?
│  ├─ NO → Continue
│  └─ YES → Show status
│     ├─ Has --force flag?
│     │  ├─ NO → Exit with message
│     │  └─ YES → "Choose (1,2,3):"
│     │     ├─ 1 → Use existing key
│     │     ├─ 2 → Create new key (backup old)
│     │     └─ 3 → Exit
│
├─ "Proceed? [Y/n]"
│  ├─ Y/y/Enter → Continue
│  └─ N/n/other → Exit
│
├─ Pattern config (unless --skip-patterns)
│  │  "Choice [1]:"
│  ├─ Enter/1 → Everything
│  ├─ 2 → Secrets only
│  ├─ 3 → Env files
│  ├─ 4 → Custom (loop: "Pattern:" until blank)
│  ├─ 5 → Skip
│  └─ other → Error
│
└─ "Encrypt now? [Y/n]"
   ├─ Y/y/Enter → Encrypt files
   └─ N/n/other → Skip
```

**Flags:**
- `--force` / `-f`: Overwrite existing key
- `--skip-patterns`: Skip pattern configuration
- `--verbose` / `-v`: Verbose output

---

### 2. `git-foil configure` [2 forks, 8 paths]

```
configure
└─ "Choice [1]:"
   ├─ Enter/1 → Everything
   ├─ 2 → Secrets only
   ├─ 3 → Env files
   ├─ 4 → Custom
   │  └─ Loop: "Pattern:" (blank to finish)
   ├─ 5 → Exit
   └─ other → Error
```

---

### 3. `git-foil unencrypt` [2 forks, 5 paths]

```
unencrypt
├─ "Continue? [y/N]"
│  ├─ y/yes → Continue to confirmation
│  └─ N/n/Enter/other → Exit with message
│
└─ "Type 'yes' to proceed:"
   ├─ yes → Unencrypt
   └─ other → Cancel
```

**Flags:**
- `--keep-key`: Preserve encryption key (don't delete)

---

### 4. `git-foil encrypt` [3 forks, 8 paths]

```
encrypt
├─ Patterns configured?
│  ├─ NO → "Configure patterns? [Y/n]"
│  │  ├─ Y/y/Enter → Open pattern config (see configure)
│  │  └─ N/n/other → Exit
│  └─ YES → Continue
│
└─ "Choose (1 or 2) [1]:"
   ├─ Enter/1 → Encrypt and stage
   ├─ 2 → Encrypt only (don't stage)
   └─ other → Error
```

---

### 5. `git-foil rekey` [1 fork, 4 paths]

```
rekey
└─ "Choose (1 or 2) [1]:"
   ├─ Enter/1 → Rekey and stage
   ├─ 2 → Rekey only (don't stage)
   └─ other → Error
```

---

### 6. `git-foil commit` [0 forks]

```
commit
└─ No prompts
   ├─ With -m → Use provided message
   └─ Without -m → Use default message
```

**Flags:**
- `-m <message>` / `--message <message>`: Commit message

---

### 7. `git-foil add-pattern <pattern>` [0 forks]

```
add-pattern
└─ No prompts
   ├─ Valid pattern → Add
   ├─ Invalid pattern → Error
   └─ No argument → Error
```

---

### 8. `git-foil remove-pattern <pattern>` [0 forks]

```
remove-pattern
└─ No prompts
   ├─ Exists → Remove
   ├─ Doesn't exist → Error
   └─ No argument → Error
```

---

### 9. `git-foil list-patterns` [0 forks]

```
list-patterns
└─ No prompts
   ├─ Has patterns → Show list
   └─ No patterns → "None configured"
```

---

### 10. `git-foil version` [0 forks]

```
version
└─ No prompts → Show version
```

---

### 11. `git-foil help` [0 forks]

```
help
├─ git-foil help → General help
├─ git-foil help patterns → Pattern syntax help
├─ git-foil --help → General help
└─ git-foil -h → General help
```

---

## Internal/Advanced Commands

**Note:** Advanced Git filter commands (`clean`, `smudge`) are documented separately in `ADVANCED.md`.

---

## Summary

### Commands to Keep in User Documentation:
1. ✅ `init` - Initialize encryption
2. ✅ `configure` - Configure patterns
3. ✅ `encrypt` - Encrypt files
4. ✅ `rekey` - Rekey files
5. ✅ `unencrypt` - Remove encryption
6. ✅ `commit` - Commit .gitattributes
7. ✅ `add-pattern` - Add pattern
8. ✅ `remove-pattern` - Remove pattern
9. ✅ `list-patterns` - List patterns
10. ✅ `version` - Show version
11. ✅ `help` - Show help

### Commands Moved to Advanced Documentation:
- ⚠️ `clean` - Git filter (internal) - See ADVANCED.md
- ⚠️ `smudge` - Git filter (internal) - See ADVANCED.md

### Total Interactive Decisions:
- **11 decision forks**
- **57 unique paths**
- **11 user-facing commands**
- **2 internal commands** (documented in ADVANCED.md)

---

## Recommendations

### 1. Reorganize documentation
- ✅ **User Guide**: 11 main commands (COMMAND_DECISION_TREE.md)
- ✅ **Advanced Guide**: `clean`, `smudge` (ADVANCED.md)
- **Development**: Implementation details (future)

### 2. Add command aliases
Consider adding shortcuts:
- `git-foil cfg` → `configure`
- `git-foil ls` → `list-patterns`
- `git-foil rm` → `remove-pattern`

### 3. Add safety confirmations
Consider adding confirmations to:
- `rekey` (destructive operation)
- `remove-pattern` (if it's the last pattern)
