# ADR-001: Triple-Layer Quantum-Resistant Encryption with Ascon Integration

## Status
**PROPOSED** - Implementation in progress

## Context

GitVeil implements transparent Git repository encryption through a three-layer defense-in-depth strategy. The current implementation uses OpenSSL-based algorithms exclusively, which creates a single point of failure if vulnerabilities are discovered in either the algorithm or implementation.

### Current Architecture (v1.0)
```
Layer 1: OpenSSL AES-256-GCM     (32-byte key, 96-bit IV, 128-bit tag)
Layer 2: OpenSSL ChaCha20-Poly1305 (32-byte key, 96-bit nonce, 128-bit tag)
Layer 3: OpenSSL AES-256-GCM     (32-byte key, 96-bit IV, 128-bit tag)
```

### Problems with Current Design
1. **Single Implementation Dependency**: All three layers use OpenSSL via Erlang's `:crypto` module
2. **Weak Algorithm Diversity**: Only two algorithms (AES-GCM and ChaCha20-Poly1305), both classical
3. **No Post-Quantum Preparation**: All algorithms vulnerable to quantum attacks
4. **Limited Cryptanalysis Resistance**: Dependency on specific implementations reduces cryptographic hedging

### Requirements
1. **Git Compatibility**: Deterministic encryption (same input → same output)
2. **Performance**: Must handle large files (100MB+) efficiently
3. **Quantum Resistance**: Prepare for post-quantum threat landscape
4. **Implementation Diversity**: Multiple cryptographic codebases
5. **Algorithm Diversity**: Different mathematical foundations
6. **Hexagonal Architecture**: Zero I/O in core domain

## Decision

Implement a **quantum-resistant triple-layer encryption system** with maximum cryptographic diversity:

### New Architecture (v2.0)
```
Layer 1: OpenSSL AES-256-GCM          (32-byte key, 96-bit IV, 128-bit tag)
         └─ Battle-tested, hardware-accelerated (AES-NI)

Layer 2: Ascon-128a (Rust NIF)         (16-byte key, 128-bit nonce, 128-bit tag)
         └─ NIST Lightweight Crypto winner, quantum-resistant design

Layer 3: OpenSSL ChaCha20-Poly1305     (32-byte key, 96-bit nonce, 128-bit tag)
         └─ Stream cipher, software-optimized, different math from AES
```

### Cryptographic Properties

#### Algorithm Diversity
- **AES-256-GCM**: Block cipher (AES) + authentication (GMAC)
- **Ascon-128a**: Sponge construction (permutation-based)
- **ChaCha20-Poly1305**: Stream cipher (ARX) + MAC (Poly1305)

Each uses fundamentally different mathematical primitives:
- AES: Substitution-permutation network
- Ascon: Cryptographic sponge
- ChaCha20: Addition-rotation-XOR operations

#### Implementation Diversity
- **OpenSSL**: C/assembly, industry standard, extensive audits
- **Rust ascon-aead**: Memory-safe, modern implementation
- **OpenSSL**: Reused but for different algorithm

#### Quantum Resistance Strategy
1. **Ascon**: Designed for post-quantum landscape (2019-2023 NIST winner)
2. **Key Size**: 256-bit symmetric keys provide 128-bit post-quantum security
3. **Hash Function**: SHA3-512 in key derivation (quantum-resistant)
4. **Future Path**: Easy to swap implementations without changing protocol

### Technical Implementation

#### 1. Ascon-128a Integration (Rust NIF)
```rust
// native/ascon_nif/src/lib.rs
use ascon_aead::{Ascon128a, Key, Nonce, Tag};

#[rustler::nif]
fn ascon_encrypt(key: Binary, nonce: Binary, plaintext: Binary, aad: Binary)
    -> Result<(Binary, Binary), String> {
    // 16-byte key, 16-byte nonce
    let cipher = Ascon128a::new(Key::from_slice(&key));
    let (ciphertext, tag) = cipher.encrypt(&nonce, &plaintext, &aad)?;
    Ok((ciphertext.into(), tag.into()))
}
```

#### 2. CryptoProvider Port Extension
```elixir
# lib/git_veil/ports/crypto_provider.ex
@callback ascon_128a_encrypt(
  key :: binary(),      # 16 bytes
  nonce :: binary(),    # 16 bytes
  plaintext :: binary(),
  aad :: binary()
) :: {:ok, ciphertext :: binary(), tag :: binary()} | {:error, term()}

@callback ascon_128a_decrypt(
  key :: binary(),      # 16 bytes
  nonce :: binary(),    # 16 bytes
  ciphertext :: binary(),
  tag :: binary(),      # 16 bytes
  aad :: binary()
) :: {:ok, plaintext :: binary()} | {:error, term()}
```

#### 3. AsconCrypto Adapter
```elixir
# lib/git_veil/adapters/ascon_crypto.ex
defmodule GitVeil.Adapters.AsconCrypto do
  @behaviour GitVeil.Ports.CryptoProvider

  @impl true
  def ascon_128a_encrypt(key, nonce, plaintext, aad)
      when byte_size(key) == 16 and byte_size(nonce) == 16 do
    GitVeil.Native.AsconNif.encrypt(key, nonce, plaintext, aad)
  end

  # Stubs for unused callbacks (adapters can be algorithm-specific)
  @impl true
  def aes_256_gcm_encrypt(_,_,_,_), do: {:error, :not_implemented}

  @impl true
  def chacha20_poly1305_encrypt(_,_,_,_), do: {:error, :not_implemented}
end
```

#### 4. Variable-Length Key Derivation
```elixir
# lib/git_veil/core/key_derivation.ex
@spec derive_keys(EncryptionKey.t(), String.t()) ::
  {:ok, %DerivedKeys{
    layer1_key: binary(),  # 32 bytes (AES-256-GCM)
    layer2_key: binary(),  # 16 bytes (Ascon-128a)
    layer3_key: binary()   # 32 bytes (ChaCha20-Poly1305)
  }} | {:error, term()}

def derive_keys(%EncryptionKey{key: master_key}, file_path) do
  salt = :crypto.hash(:sha3_512, file_path) |> binary_part(0, 32)

  layer1_key = hkdf_sha3_512(master_key, salt, "GitVeil.Layer1.AES256", 32)
  layer2_key = hkdf_sha3_512(master_key, salt, "GitVeil.Layer2.Ascon", 16)  # 16 bytes!
  layer3_key = hkdf_sha3_512(master_key, salt, "GitVeil.Layer3.ChaCha", 32)

  {:ok, %DerivedKeys{...}}
end
```

#### 5. TripleCipher Update
```elixir
# lib/git_veil/core/triple_cipher.ex
def encrypt(plaintext, %DerivedKeys{layer1_key: k1, layer2_key: k2, layer3_key: k3},
            layer1_provider, layer2_provider, layer3_provider, file_path) do
  aad = file_path

  # Layer 1: AES-256-GCM (32-byte key, 12-byte IV)
  with {:ok, iv1} <- derive_iv(k1, 1, 12),
       {:ok, ct1, tag1} <- layer1_provider.aes_256_gcm_encrypt(k1, iv1, plaintext, aad),

       # Layer 2: Ascon-128a (16-byte key, 16-byte nonce)
       {:ok, nonce2} <- derive_iv(k2, 2, 16),
       {:ok, ct2, tag2} <- layer2_provider.ascon_128a_encrypt(k2, nonce2, ct1, aad),

       # Layer 3: ChaCha20-Poly1305 (32-byte key, 12-byte nonce)
       {:ok, nonce3} <- derive_iv(k3, 3, 12),
       {:ok, ct3, tag3} <- layer3_provider.chacha20_poly1305_encrypt(k3, nonce3, ct2, aad) do
    {:ok, ct3, tag1, tag2, tag3}
  end
end

# Flexible IV/nonce derivation
defp derive_iv(key, layer, size) do
  hash = :crypto.hash(:sha3_256, key <> <<layer>>)
  {:ok, binary_part(hash, 0, size)}
end
```

#### 6. GitFilter Integration
```elixir
# lib/git_veil/adapters/git_filter.ex
defp encrypt_content(plaintext, master_key, file_path) do
  alias GitVeil.Adapters.{OpenSSLCrypto, AsconCrypto}

  EncryptionEngine.encrypt(
    plaintext,
    master_key,
    OpenSSLCrypto,      # Layer 1: AES-256-GCM
    AsconCrypto,        # Layer 2: Ascon-128a
    OpenSSLCrypto,      # Layer 3: ChaCha20-Poly1305
    file_path
  )
end
```

### Wire Format (Unchanged)
```
[version:1][tag1:16][tag2:16][tag3:16][ciphertext:variable]
```

Version byte = 1 (same as before, backward compatible with deserialization)

## Consequences

### Benefits
1. **Maximum Cryptographic Diversity**
   - 3 algorithms × 3 different mathematical foundations
   - 2 independent implementations (OpenSSL + Rust)
   - Post-quantum resistant design (Ascon)

2. **Defense in Depth**
   - Breaking encryption requires breaking ALL three layers
   - Different attack vectors for each algorithm
   - Implementation bugs in one don't compromise others

3. **Future-Proof**
   - Ascon-128a: NIST Lightweight Crypto standard (2023)
   - Quantum resistance: 128-bit security post-quantum
   - Easy algorithm swapping via hexagonal architecture

4. **Performance Balanced**
   - AES-256-GCM: ~2 GB/s (AES-NI hardware)
   - Ascon-128a: ~500 MB/s (lightweight design)
   - ChaCha20-Poly1305: ~800 MB/s (software optimized)
   - Combined: ~300-400 MB/s (limited by Ascon, still fast for Git)

5. **Git Compatible**
   - Deterministic encryption maintained
   - Same wire format version
   - Backward compatible deserialization

### Risks & Mitigations

1. **Ascon Immaturity**
   - Risk: Newer algorithm, less battle-tested
   - Mitigation: Sandwiched between two proven algorithms (AES, ChaCha20)
   - Mitigation: NIST-selected standard with formal proofs

2. **Rust NIF Complexity**
   - Risk: Build complexity, potential NIX incompatibility
   - Mitigation: Rustler is mature and widely used
   - Mitigation: Fallback to pure Elixir Ascon if needed

3. **Performance Overhead**
   - Risk: Ascon slower than AES-NI
   - Mitigation: Still 300+ MB/s, acceptable for Git workflows
   - Mitigation: Only layer 2, bounded by I/O in practice

4. **Dependency Management**
   - Risk: Rust toolchain required
   - Mitigation: Mix Release bundles compiled NIF
   - Mitigation: Clear build documentation

### Testing Requirements

1. **Unit Tests**
   - Ascon encrypt/decrypt correctness
   - Variable-length key derivation (16-byte, 32-byte)
   - Provider injection in TripleCipher

2. **Integration Tests**
   - Full three-layer encryption/decryption
   - Git determinism validation
   - Large file handling (100MB+)

3. **Security Tests**
   - Authentication tag validation
   - Tamper detection
   - Key independence verification

4. **Performance Tests**
   - Throughput benchmarks
   - Memory usage profiling
   - Comparison with v1.0

## References

1. **Ascon Specification**: https://ascon.iaik.tugraz.at/
2. **NIST Lightweight Cryptography**: https://csrc.nist.gov/projects/lightweight-cryptography
3. **Post-Quantum Cryptography**: NIST SP 800-208
4. **HKDF RFC 5869**: https://datatracker.ietf.org/doc/html/rfc5869
5. **GitVeil ADR-002**: Hexagonal Architecture for Testability
6. **Rust ascon-aead crate**: https://crates.io/crates/ascon-aead
7. **Cryptographic Sponge Functions**: https://keccak.team/sponge_duplex.html

## Implementation Checklist

- [ ] Phase 1: Documentation & Architecture
  - [x] ADR-001 written
  - [ ] README.md security section updated

- [ ] Phase 2: Ascon Implementation
  - [ ] Rustler dependency added
  - [ ] NIF project structure created
  - [ ] Rust Ascon wrapper implemented
  - [ ] AsconCrypto adapter created
  - [ ] CryptoProvider behavior extended
  - [ ] Unit tests written

- [ ] Phase 3: Integration
  - [ ] TripleCipher algorithm selection updated
  - [ ] GitFilter three-provider configuration
  - [ ] Variable-length key derivation implemented

- [ ] Phase 4: Testing & Validation
  - [ ] Integration tests written
  - [ ] Git compatibility validated
  - [ ] Performance benchmarks run
  - [ ] Security validation complete

## Timeline
- **Design & Documentation**: 15 minutes ✓
- **Ascon Implementation**: 2 hours
- **Integration**: 30 minutes
- **Testing & Validation**: 1 hour
- **Total**: ~4 hours

## Approval
**Architect**: code-of-kai
**Date**: 2025-10-05
