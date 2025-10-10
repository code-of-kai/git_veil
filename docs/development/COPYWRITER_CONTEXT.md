# GitFoil Copywriting Context

## Project Overview
GitFoil is a triple-layer quantum-resistant encryption system for Git repositories. It provides military-grade security with zero workflow friction.

## Target Audience
**Developers who:**
- Care deeply about security but hate complexity
- Want protection against future quantum computers
- Need Git to "just work" with zero extra commands
- Understand that secrets in repos are a real threat
- Appreciate elegant engineering

## Tone & Style Guide

**Steve Jobs Approach:**
- Short sentences. Punchy. Declarative.
- Concrete benefits, not abstract features
- No marketing fluff or superlatives
- Technical credibility through specifics (NIST winner, not "award-winning")
- Focus on what it does FOR YOU

**Good examples:**
- "Set it up. Then forget it exists."
- "Crack one file, the rest stay locked."
- "Piggybacks invisibly on every Git command."

**Bad examples:**
- "GitFoil leverages cutting-edge cryptographic primitives..."
- "Our revolutionary approach to security..."
- "Industry-leading encryption solution..."

## Core Differentiators

### 1. All-or-Nothing Security
**The insight:** Breaking one layer gives ZERO feedback.

Each encryption layer uses AEAD (Authenticated Encryption). When you decrypt Layer 3:
- Wrong key → Authentication failure (no output)
- Right key → Layer 2 ciphertext (looks like random noise)

**The attacker cannot tell if they succeeded.** They could spend years cracking Layer 3, succeed, and have NO IDEA because the Layer 2 ciphertext they get looks identical to garbage.

**Analogy:** Like a safe with three locks. You don't hear a "click" when you crack one lock. You only know when all three open.

### 2. Multiplicative Security
While brute-force is limited by the 256-bit master key (2^256), **algorithmic attacks face multiplicative odds:**

```
P(break GitFoil) = P(break AES) × P(break Ascon) × P(break ChaCha20)
```

If each has 1% chance of a critical flaw:
- Breaking one: 1% (0.01)
- Breaking all three: 0.0001% (0.01 × 0.01 × 0.01)
- **10,000× better** against cryptographic breakthroughs

### 3. File Isolation
Each file gets unique encryption keys via HKDF with path-based salt.

**Impact:** Crack database.env, attackers still can't decrypt api_keys.json

### 4. Invisible Integration
Uses Git clean/smudge filters. Once configured:
- `git commit` → Automatic encryption
- `git pull` → Automatic decryption
- `git diff` → Works on plaintext
- Zero extra commands. Zero workflow changes.

### 5. NIST-Validated Quantum Resistance
**Ascon-128a** won NIST's Lightweight Cryptography competition (February 2023).
- Government-vetted
- Designed for post-quantum era
- Standardized, not experimental

## Three-Layer Architecture

### Implementation Diversity
- **Layer 1: OpenSSL (AES-256-GCM)** - Battle-tested, decades in production, hardware-accelerated
- **Layer 2: Rust NIF (Ascon-128a)** - Memory-safe, NIST prize winner, quantum-resistant
- **Layer 3: OpenSSL (ChaCha20-Poly1305)** - Constant-time, side-channel resistant

### Why Three Different Implementations?
- **OpenSSL vulnerability?** Rust layer still protects you
- **Quantum computer breaks AES?** Ascon stays strong
- **New attack on ChaCha20?** AES + Ascon still encrypted

## Key Technical Points (Don't Oversimplify)

### Deterministic Encryption
Same file content → Same ciphertext (required for Git's content-addressable storage)
- Enables Git deduplication
- No spurious diffs from random nonces
- Merge conflicts detected accurately

**Trade-off:** Pattern analysis possible (mitigated by file-specific keys + triple layers)

### Performance
- Combined throughput: ~380 MB/s (M1 Pro)
- Small files: 50-100/sec
- Git overhead: <5% vs unencrypted
- Bottleneck: Ascon layer (software-only, no hardware acceleration yet)

### Master Key Security
Stored in `.gitfoil/master.key`:
- Auto-gitignored (never committed)
- Key loss = permanent data loss
- Rotate with `git-foil rekey`
- Enterprise: HSM/TPM integration coming

## Messaging Priorities

**Primary message:**
"Military-grade security. Zero workflow changes."

**Secondary messages:**
1. Future-proof (quantum-resistant)
2. Defense in depth (three layers, multiplicative security)
3. File isolation (breach one ≠ breach all)
4. Dead simple setup

**Avoid:**
- "Unbreakable" claims (nothing is)
- Complexity porn (algorithm details for their own sake)
- Security theater (vague "enterprise-grade" claims)

## Project Status
**Alpha - Not production ready**
- Core crypto: Solid (18/18 tests passing)
- CLI commands: Working (init, pattern, encrypt)
- Missing: HSM support, multi-user key sharing, GUI
- Use case: Personal repos, side projects, learning

## Visual Language

**Diagrams included:**
- Encryption pipeline (plaintext → three layers → Git)
- Decryption pipeline (Git → three layers → plaintext)
- Shows authentication tags, key derivation, wire format

**Metaphors that work:**
- Safe with three locks
- Layers of an onion
- Russian nesting dolls (but for security)

**Metaphors to avoid:**
- Military imagery (overdone)
- Shields/armor (cliché)
- Impenetrable fortress (false promise)

## Competitive Context

**Not competing with:**
- git-crypt (single layer, gpg-based)
- git-secret (gpg wrapper)
- Vault/secret managers (different use case)

**Unique position:**
- Only triple-layer Git encryption
- Only quantum-resistant Git encryption
- Only deterministic AEAD Git encryption

## Call to Action

**Primary CTA:** Try it on a test repo
**Secondary CTA:** Read the security architecture
**Tertiary CTA:** Star the repo, contribute

**NOT:** "Download now" (it's alpha), "Buy" (it's free), "Enterprise demo" (not ready)

---

## Attached Reference Files

See the following files for complete technical context:

1. **README.md** - Current project page (rewrite this)
2. **docs/ADR-001-triple-layer-quantum-resistant-encryption.md** - Deep architectural rationale
3. **demo_ascon.exs** - Live demo showing encryption/decryption
4. **lib/git_foil/core/encryption_engine.ex** - Core implementation
5. **test/git_foil/core/encryption_engine_test.exs** - What it guarantees

---

## Copywriting Task

**Rewrite the GitHub README.md** to communicate GitFoil's value proposition using:
- Steve Jobs brevity and punch
- Technical credibility without jargon overload
- Focus on the three magic moments:
  1. Dead simple setup
  2. Invisible piggybacking on Git
  3. All-or-nothing security that multiplies with each layer

**Preserve:**
- Installation instructions (they work)
- Architecture diagrams (they're good)
- Performance benchmarks (concrete data)
- Security considerations (important caveats)

**Improve:**
- Opening hook (grab attention immediately)
- Feature presentation (show don't tell)
- Security explanation (make multiplicative security intuitive)
- Getting started flow (reduce friction)

**Length:** Keep it scannable. Developers skim. Use headings, bullets, code blocks.

**Avoid:**
- Wall of text
- Burying the lede (quantum resistance should be prominent)
- Over-explaining (trust the reader's intelligence)
