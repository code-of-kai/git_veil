# GitFoil Multi-User Setup Guide

## Architecture Analysis: Single vs Multi-User

### Current Design: **Single-User or Shared-Key Team Model**

GitFoil is currently designed for **one of two scenarios**:

1. **Single developer** using the repo on one or more machines
2. **Team of developers** who all share the **same master key file**

## How It Works

### Key Generation (No Password Required)

**GitFoil does NOT use password-based encryption.** Instead:

1. When you run `git-foil init`, it generates a **random post-quantum keypair**:
   - **Kyber1024** public/private key pair (post-quantum)
   - **Classical** 32-byte random keys
   - No password prompt, no Argon2id derivation

2. The keypair is stored in `.git/git_foil/master.key`:
   - Location: `.git/git_foil/master.key`
   - Permissions: `0600` (owner read/write only)
   - Format: Erlang binary term format
   - **NOT encrypted at rest** (plaintext binary file)
   - **NOT committed to Git** (stored in `.git/` directory)

3. Master encryption key derivation:
   ```elixir
   master_key = SHA-512(classical_secret || pq_secret)[0..31]  # First 32 bytes
   ```

4. Per-file key derivation:
   ```elixir
   salt = SHA3-512(file_path)[0..31]
   layer1_key = HKDF-SHA3-512(master_key, salt, "GitFoil.Layer1.AES256", 32)
   layer2_key = HKDF-SHA3-512(master_key, salt, "GitFoil.Layer2.AEGIS256", 32)
   # ... and so on for all 6 layers
   ```

### Security Model

✅ **What's secure:**
- Encrypted files in Git commits (6-layer encryption)
- Encrypted files on GitHub/remote (ciphertext only)
- Per-file key derivation (cracking one file doesn't help with others)

❌ **What's NOT secure:**
- **Master key file is unencrypted** on disk (`.git/git_foil/master.key`)
- Anyone with filesystem access can read `master.key`
- No password protection on the key file itself
- If someone steals your laptop, they have your keys

## Multi-User Scenarios

### Scenario 1: New Team Member Joining

**Question:** How does a new developer get access to the encrypted repo?

**Answer:** They need a copy of the `master.key` file.

**Steps:**

1. **Existing team member** exports the master key:
   ```bash
   # On existing team member's machine
   cd /path/to/repo

   # Copy the master key file
   cp .git/git_foil/master.key ~/master.key.backup

   # Share this file securely (see "Secure Sharing" below)
   ```

2. **New team member** clones the repo:
   ```bash
   git clone https://github.com/your-org/your-repo.git
   cd your-repo
   ```

3. **New team member** receives the `master.key` file (via secure channel) and places it:
   ```bash
   # Create the directory
   mkdir -p .git/git_foil

   # Copy the shared master key
   cp ~/received-master.key .git/git_foil/master.key

   # Set correct permissions
   chmod 600 .git/git_foil/master.key
   ```

4. **New team member** configures Git filters:
   ```bash
   # Install git-foil binary (build from source or copy from team)
   mix escript.build

   # Configure filters (this just sets up git config, doesn't generate new keys)
   # Actually, there's no command for this - they may need to manually set:
   git config filter.gitfoil.clean "git-foil clean %f"
   git config filter.gitfoil.smudge "git-foil smudge %f"
   git config filter.gitfoil.required true
   ```

5. **Verify** it works:
   ```bash
   # Pull encrypted files - they should decrypt automatically
   git pull

   # Files should be readable plaintext in working directory
   cat secrets/.env
   ```

### Scenario 2: Setting Up GitFoil on a New Machine (Same Developer)

**Question:** I have GitFoil set up on my work laptop. Now I want to use it on my home desktop. What do I do?

**Answer:** Transfer your `master.key` file from laptop to desktop.

**Steps:**

1. **On work laptop**, back up your master key:
   ```bash
   cd /path/to/repo
   cp .git/git_foil/master.key ~/Dropbox/gitfoil-backup/master.key
   # Or use USB drive, encrypted cloud storage, etc.
   ```

2. **On home desktop**, clone the repo:
   ```bash
   git clone https://github.com/your-org/your-repo.git
   cd your-repo
   ```

3. **On home desktop**, restore the master key:
   ```bash
   mkdir -p .git/git_foil
   cp ~/Dropbox/gitfoil-backup/master.key .git/git_foil/master.key
   chmod 600 .git/git_foil/master.key
   ```

4. **On home desktop**, set up git-foil and filters:
   ```bash
   # Build or copy git-foil binary
   mix escript.build

   # Configure git filters
   git config filter.gitfoil.clean "git-foil clean %f"
   git config filter.gitfoil.smudge "git-foil smudge %f"
   git config filter.gitfoil.required true
   ```

5. **Test** decryption:
   ```bash
   git status  # Files should checkout decrypted
   cat secrets/.env  # Should show plaintext
   ```

## Secure Sharing of master.key

### ❌ DO NOT:
- Email the `master.key` file unencrypted
- Commit `master.key` to the repository
- Store `master.key` in plaintext on Slack/Discord/etc.
- Share via unencrypted cloud storage

### ✅ DO:
1. **GPG-encrypt the key file:**
   ```bash
   # Encrypt for recipient
   gpg --encrypt --recipient team-member@email.com master.key
   # Send master.key.gpg via any channel
   ```

2. **Use a password manager with secure sharing:**
   - 1Password (shared vaults)
   - Bitwarden (organization sharing)
   - LastPass (shared folders)
   - Upload `master.key` as a secure note

3. **Use encrypted file transfer:**
   - Magic Wormhole: `wormhole send master.key`
   - Keybase: Encrypted file sharing
   - Signal: Send as file attachment

4. **In-person transfer:**
   - USB drive
   - QR code (for small keys)
   - Local network transfer over SSH

## Current Limitations

### 1. **No Password Protection**

**Issue:** The README mentions "master password" but **GitFoil doesn't actually use passwords**.

**Impact:**
- Anyone with filesystem access to `.git/git_foil/master.key` can decrypt all files
- No protection against laptop theft (disk encryption is your only defense)
- No ability to change the "password" (you'd have to re-generate keys and re-encrypt everything)

**Recommendation:** Update README to accurately describe the key-based (not password-based) model.

### 2. **No Key Encryption at Rest**

**Issue:** `master.key` is stored as plaintext binary on disk.

**Current code comment:**
```elixir
# lib/git_foil/adapters/file_key_storage.ex:18
# TODO: Add encryption-at-rest for master.key
```

**Impact:**
- Master key is vulnerable to filesystem-level attacks
- Malware, disk imaging, or forensics can extract the key
- No additional layer of protection beyond filesystem permissions

**Possible Enhancement:**
```elixir
# Future: Password-protect the master.key file
def store_keypair(keypair, password) do
  serialized = :erlang.term_to_binary(keypair)

  # Derive encryption key from password using Argon2id
  salt = :crypto.strong_rand_bytes(32)
  password_key = :crypto.argon2id_hash(password, salt, ...)

  # Encrypt the keypair with AES-256-GCM
  {encrypted, tag} = :crypto.crypto_one_time_aead(:aes_256_gcm, password_key, iv, serialized, "")

  # Store: salt || iv || tag || encrypted_keypair
  File.write(key_path, salt <> iv <> tag <> encrypted)
end
```

### 3. **No Per-User Keys (Single Shared Key)**

**Issue:** All team members use the same `master.key` file.

**Impact:**
- Can't revoke access for a single team member (must re-key entire repo)
- Can't track who encrypted/decrypted files
- If one team member's laptop is compromised, entire team must rotate keys

**Alternative Design (Not Currently Implemented):**

A true multi-user system would use **hybrid encryption**:

1. Each team member has their own keypair
2. File encryption key (DEK - Data Encryption Key) is generated randomly per file
3. DEK is encrypted with each team member's public key
4. Each encrypted DEK is stored in file metadata

```
File Structure:
[encrypted_dek_for_alice][encrypted_dek_for_bob][encrypted_dek_for_carol][ciphertext]

Alice's key can decrypt → DEK → file
Bob's key can decrypt → DEK → same file
Carol's key can decrypt → DEK → same file
```

**Benefits:**
- Revoke Carol: Just remove her encrypted DEK from all files
- Add new member: Encrypt DEK with their public key
- Per-user audit trail

**Downside:**
- More complex implementation
- Larger file overhead (N encrypted DEKs per file)
- Requires key distribution infrastructure

## Recommendations for README Update

The current README is **misleading** in several places:

### ❌ Current README Says:
> "Enter master password (32+ characters recommended)"

**Reality:** There is **no password prompt** during `git-foil init`. It generates a random keypair.

### ❌ Current README Says:
> "Master key: 256-bit derived via Argon2id from password"

**Reality:** Master key is derived via `SHA-512(classical_secret || pq_secret)` from a randomly generated keypair. **No Argon2id, no password.**

### ✅ Should Say:

```markdown
## Setup

### Initialize Your Repository

```bash
cd /path/to/your/repo
git-foil init

# No password required - generates random quantum-resistant keys
# Keys stored in .git/git_foil/master.key
```

**That's it.** GitFoil generates a cryptographically random keypair and hooks into Git.

### Key Storage

- **Location:** `.git/git_foil/master.key`
- **Format:** Binary keypair (Kyber1024 + classical)
- **Permissions:** 0600 (owner read/write only)
- **Security:** Protected by filesystem permissions only
- **Important:** Back up this file! Without it, you cannot decrypt your files.

## Team Usage

### Setup for Teams

1. **Initial setup** (one team member):
   ```bash
   git-foil init  # Generates master.key
   git add .gitattributes
   git commit -m "Add GitFoil encryption"
   git push
   ```

2. **Share the master key** securely:
   - **Export:** `cp .git/git_foil/master.key ~/master-key-backup.bin`
   - **Share via:** GPG encryption, password manager, encrypted chat
   - **DO NOT** commit to Git or email unencrypted

3. **Each team member** sets up:
   ```bash
   git clone https://github.com/your-org/your-repo.git
   cd your-repo

   # Receive master.key from team lead (via secure channel)
   mkdir -p .git/git_foil
   cp ~/received-master.key .git/git_foil/master.key
   chmod 600 .git/git_foil/master.key

   # Configure git filters
   git config filter.gitfoil.clean "git-foil clean %f"
   git config filter.gitfoil.smudge "git-foil smudge %f"
   git config filter.gitfoil.required true
   ```

4. **Everyone works normally:**
   ```bash
   git pull   # Decrypts incoming changes
   git add .
   git commit
   git push   # Encrypts outgoing changes
   ```

### What's Shared

✅ **The same `master.key` file** - copied to each team member's `.git/git_foil/` directory
✅ **The same encryption keys** - everyone can decrypt each other's commits
✅ **The `.gitattributes` file** - defines which files are encrypted (committed to repo)

❌ **NOT shared via Git** - the `master.key` file itself (stored locally, never committed)
```

## Conclusion

**GitFoil is designed for:**
- ✅ Single developers using multiple machines
- ✅ Small trusted teams sharing a single master key
- ✅ Protecting files from GitHub/remote access

**GitFoil is NOT designed for:**
- ❌ Large teams with dynamic membership
- ❌ Per-user access control or revocation
- ❌ Zero-knowledge encryption (key is plaintext on disk)
- ❌ Password-based key derivation (despite README claims)

**To use GitFoil with a team:**
1. One person runs `git-foil init` and generates the master key
2. Securely share the `.git/git_foil/master.key` file with all team members
3. Each team member places the key in their local `.git/git_foil/` directory
4. Everyone can now encrypt/decrypt files seamlessly

**The key insight:** GitFoil uses a **shared secret model**, not a **multi-user access control model**. It's more like a shared password manager vault than per-user GPG encryption.
