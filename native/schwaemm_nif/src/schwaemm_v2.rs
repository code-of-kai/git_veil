/// Schwaemm256-256 AEAD implementation - Version 2
///
/// Complete rewrite based on NIST reference implementation.
/// Follows the exact structure from the C reference code.

use crate::sparkle::sparkle_512;

const RATE_WORDS: usize = 8;   // 256 bits
const CAP_WORDS: usize = 8;    // 256 bits
const STATE_WORDS: usize = 16; // 512 bits total
const RATE_BRANS: usize = 4;   // 4 branches in rate
const CAP_BRANS: usize = 4;    // 4 branches in capacity

const RATE_BYTES: usize = 32;  // 256 bits
const TAG_BYTES: usize = 32;   // 256 bits
const KEY_BYTES: usize = 32;   // 256 bits
const NONCE_BYTES: usize = 32; // 256 bits

const SPARKLE_STEPS_SLIM: usize = 8;
const SPARKLE_STEPS_BIG: usize = 12;

// Domain separation constants
// For Schwaemm256-256: CAP_BRANS = 4, so (1 << 4) = 16
const CONST_A0: u32 = ((0 ^ 16) as u32) << 24; // 0x10000000
const CONST_A1: u32 = ((1 ^ 16) as u32) << 24; // 0x11000000
const CONST_M2: u32 = ((2 ^ 16) as u32) << 24; // 0x12000000
const CONST_M3: u32 = ((3 ^ 16) as u32) << 24; // 0x13000000

/// SparkleState structure matching the C reference
/// Organized as x[] and y[] arrays, not flat
#[derive(Clone)]
struct SparkleState {
    x: [u32; 8],
    y: [u32; 8],
}

/// Convert bytes to words (little-endian)
#[inline]
fn bytes_to_words_le(bytes: &[u8]) -> Vec<u32> {
    bytes
        .chunks(4)
        .map(|chunk| {
            let mut buf = [0u8; 4];
            buf[..chunk.len()].copy_from_slice(chunk);
            u32::from_le_bytes(buf)
        })
        .collect()
}

/// Convert words to bytes (little-endian)
#[inline]
fn words_to_bytes_le(words: &[u32], bytes: &mut [u8]) {
    for (i, &word) in words.iter().enumerate() {
        let word_bytes = word.to_le_bytes();
        let start = i * 4;
        let end = (start + 4).min(bytes.len());
        if start < bytes.len() {
            bytes[start..end].copy_from_slice(&word_bytes[..(end - start)]);
        }
    }
}

/// Rho and rate-whitening for authentication of associated data
fn rho_whi_aut(state: &mut SparkleState, input: &[u8]) {
    // Create zero-padded buffer
    let mut inbuf_bytes = [0u8; RATE_BYTES];
    inbuf_bytes[..input.len()].copy_from_slice(input);

    // Add padding if partial block
    if input.len() < RATE_BYTES {
        inbuf_bytes[input.len()] = 0x80;
    }

    // Convert to words
    let inbuf = bytes_to_words_le(&inbuf_bytes)
        .try_into()
        .unwrap_or([0u32; RATE_WORDS]);

    // Rho1 part 1: Feistel swap of rate-part
    // Swaps first half with second half of rate (x[0..1] with x[2..3], y[0..1] with y[2..3])
    let b = RATE_BRANS / 2; // b = 2
    for i in 0..b {
        // Swap x values
        let tmp = state.x[i];
        state.x[i] = state.x[i + b];
        state.x[i + b] ^= tmp;

        // Swap y values
        let tmp = state.y[i];
        state.y[i] = state.y[i + b];
        state.y[i + b] ^= tmp;
    }

    // Rho1 part 2: XOR associated data into rate
    for i in 0..RATE_BRANS {
        state.x[i] ^= inbuf[2 * i];
        state.y[i] ^= inbuf[2 * i + 1];
    }

    // Rate-whitening: capacity XORed to rate
    for i in 0..RATE_BRANS {
        state.x[i] ^= state.x[RATE_BRANS + (i % CAP_BRANS)];
        state.y[i] ^= state.y[RATE_BRANS + (i % CAP_BRANS)];
    }
}

/// Rho and rate-whitening for encryption
fn rho_whi_enc(state: &mut SparkleState, output: &mut [u8], input: &[u8]) {
    // Create zero-padded buffer
    let mut inbuf_bytes = [0u8; RATE_BYTES];
    inbuf_bytes[..input.len()].copy_from_slice(input);

    // Add padding if partial block
    if input.len() < RATE_BYTES {
        inbuf_bytes[input.len()] = 0x80;
    }

    // Convert to words
    let inbuf = bytes_to_words_le(&inbuf_bytes)
        .try_into()
        .unwrap_or([0u32; RATE_WORDS]);
    let mut outbuf = [0u32; RATE_WORDS];

    // Rho2: ciphertext = plaintext XOR rate-part
    for i in 0..RATE_BRANS {
        outbuf[2 * i] = inbuf[2 * i] ^ state.x[i];
        outbuf[2 * i + 1] = inbuf[2 * i + 1] ^ state.y[i];
    }

    // Rho1 part 1: Feistel swap of rate-part
    let b = RATE_BRANS / 2;
    for i in 0..b {
        // Swap x values
        let tmp = state.x[i];
        state.x[i] = state.x[i + b];
        state.x[i + b] ^= tmp;

        // Swap y values
        let tmp = state.y[i];
        state.y[i] = state.y[i + b];
        state.y[i + b] ^= tmp;
    }

    // Rho1 part 2: XOR plaintext into rate
    for i in 0..RATE_BRANS {
        state.x[i] ^= inbuf[2 * i];
        state.y[i] ^= inbuf[2 * i + 1];
    }

    // Rate-whitening
    for i in 0..RATE_BRANS {
        state.x[i] ^= state.x[RATE_BRANS + (i % CAP_BRANS)];
        state.y[i] ^= state.y[RATE_BRANS + (i % CAP_BRANS)];
    }

    // Extract ciphertext
    words_to_bytes_le(&outbuf, output);
}

/// Rho and rate-whitening for decryption
fn rho_whi_dec(state: &mut SparkleState, output: &mut [u8], input: &[u8]) {
    // Create zero-padded buffer
    let mut inbuf_bytes = [0u8; RATE_BYTES];
    inbuf_bytes[..input.len()].copy_from_slice(input);

    // Save original state for full-block processing
    let statebuf = state.clone();

    // Add padding if partial block
    if input.len() < RATE_BYTES {
        inbuf_bytes[input.len()] = 0x80;
    }

    // Convert to words
    let inbuf = bytes_to_words_le(&inbuf_bytes)
        .try_into()
        .unwrap_or([0u32; RATE_WORDS]);
    let mut outbuf = [0u32; RATE_WORDS];

    // Rho2': plaintext = ciphertext XOR rate-part
    for i in 0..RATE_BRANS {
        outbuf[2 * i] = inbuf[2 * i] ^ state.x[i];
        outbuf[2 * i + 1] = inbuf[2 * i + 1] ^ state.y[i];
    }

    // Rho1' part 1: Feistel swap of rate-part
    let b = RATE_BRANS / 2;
    for i in 0..b {
        let tmp = state.x[i];
        state.x[i] = state.x[i + b];
        state.x[i + b] ^= tmp;

        let tmp = state.y[i];
        state.y[i] = state.y[i + b];
        state.y[i + b] ^= tmp;
    }

    // Rho1' part 2: Different for partial vs full blocks
    if input.len() < RATE_BYTES {
        // Partial block: pad plaintext and XOR into state
        let mut outbuf_bytes: Vec<u8> = outbuf.iter()
            .flat_map(|&w| w.to_le_bytes().to_vec())
            .collect();
        outbuf_bytes[input.len()..].fill(0);
        outbuf_bytes[input.len()] = 0x80;

        let outbuf_padded = bytes_to_words_le(&outbuf_bytes)
            .try_into()
            .unwrap_or([0u32; RATE_WORDS]);

        for i in 0..RATE_BRANS {
            state.x[i] ^= outbuf_padded[2 * i];
            state.y[i] ^= outbuf_padded[2 * i + 1];
        }
    } else {
        // Full block: XOR with (original_state XOR ciphertext)
        for i in 0..RATE_BRANS {
            state.x[i] ^= statebuf.x[i] ^ inbuf[2 * i];
            state.y[i] ^= statebuf.y[i] ^ inbuf[2 * i + 1];
        }
    }

    // Rate-whitening
    for i in 0..RATE_BRANS {
        state.x[i] ^= state.x[RATE_BRANS + (i % CAP_BRANS)];
        state.y[i] ^= state.y[RATE_BRANS + (i % CAP_BRANS)];
    }

    // Extract plaintext
    words_to_bytes_le(&outbuf, output);
}

/// Convert SparkleState to flat array for permutation
fn state_to_flat(state: &SparkleState) -> [u32; STATE_WORDS] {
    let mut flat = [0u32; STATE_WORDS];
    for i in 0..8 {
        flat[2 * i] = state.x[i];
        flat[2 * i + 1] = state.y[i];
    }
    flat
}

/// Convert flat array back to SparkleState
fn flat_to_state(flat: &[u32; STATE_WORDS]) -> SparkleState {
    let mut state = SparkleState {
        x: [0u32; 8],
        y: [0u32; 8],
    };
    for i in 0..8 {
        state.x[i] = flat[2 * i];
        state.y[i] = flat[2 * i + 1];
    }
    state
}

/// Apply Sparkle permutation to SparkleState
fn sparkle_state(state: &mut SparkleState, steps: usize) {
    let mut flat = state_to_flat(state);
    sparkle_512(&mut flat, steps);
    *state = flat_to_state(&flat);
}

/// Initialize state with nonce and key
fn initialize(key: &[u8; KEY_BYTES], nonce: &[u8; NONCE_BYTES]) -> SparkleState {
    let mut state = SparkleState {
        x: [0u32; 8],
        y: [0u32; 8],
    };

    let nonce_words = bytes_to_words_le(nonce);
    let key_words = bytes_to_words_le(key);

    // Load nonce into rate-part
    for i in 0..4 {
        state.x[i] = nonce_words[2 * i];
        state.y[i] = nonce_words[2 * i + 1];
    }

    // Load key into capacity-part
    for i in 0..4 {
        state.x[RATE_BRANS + i] = key_words[2 * i];
        state.y[RATE_BRANS + i] = key_words[2 * i + 1];
    }

    // Execute SPARKLE with big number of steps
    sparkle_state(&mut state, SPARKLE_STEPS_BIG);

    state
}

/// Process associated data
fn process_assoc_data(state: &mut SparkleState, aad: &[u8]) {
    if aad.is_empty() {
        return;
    }

    let mut offset = 0;

    // Main authentication loop
    while aad.len() - offset > RATE_BYTES {
        rho_whi_aut(state, &aad[offset..offset + RATE_BYTES]);
        sparkle_state(state, SPARKLE_STEPS_SLIM);
        offset += RATE_BYTES;
    }

    // Authentication of last block
    let remaining = &aad[offset..];
    let const_val = if remaining.len() < RATE_BYTES {
        CONST_A0
    } else {
        CONST_A1
    };
    state.y[7] ^= const_val; // XOR to last y-word (index 7)

    rho_whi_aut(state, remaining);
    sparkle_state(state, SPARKLE_STEPS_BIG);
}

/// Process plaintext (encryption)
fn process_plaintext(state: &mut SparkleState, plaintext: &[u8]) -> Vec<u8> {
    if plaintext.is_empty() {
        return Vec::new();
    }

    let mut ciphertext = Vec::with_capacity(plaintext.len());
    let mut offset = 0;

    // Main encryption loop
    while plaintext.len() - offset > RATE_BYTES {
        let mut ct_block = vec![0u8; RATE_BYTES];
        rho_whi_enc(state, &mut ct_block, &plaintext[offset..offset + RATE_BYTES]);
        ciphertext.extend_from_slice(&ct_block);
        sparkle_state(state, SPARKLE_STEPS_SLIM);
        offset += RATE_BYTES;
    }

    // Encryption of last block
    let remaining = &plaintext[offset..];
    let const_val = if remaining.len() < RATE_BYTES {
        CONST_M2
    } else {
        CONST_M3
    };
    state.y[7] ^= const_val; // XOR to last y-word

    let mut ct_block = vec![0u8; remaining.len()];
    rho_whi_enc(state, &mut ct_block, remaining);
    ciphertext.extend_from_slice(&ct_block);
    sparkle_state(state, SPARKLE_STEPS_BIG);

    ciphertext
}

/// Finalize by adding key to capacity
fn finalize(state: &mut SparkleState, key: &[u8; KEY_BYTES]) {
    let key_words = bytes_to_words_le(key);

    for i in 0..4 {
        state.x[RATE_BRANS + i] ^= key_words[2 * i];
        state.y[RATE_BRANS + i] ^= key_words[2 * i + 1];
    }
}

/// Generate authentication tag from capacity
fn generate_tag(state: &SparkleState) -> [u8; TAG_BYTES] {
    let mut tag_words = Vec::new();
    for i in 0..4 {
        tag_words.push(state.x[RATE_BRANS + i]);
        tag_words.push(state.y[RATE_BRANS + i]);
    }

    let mut tag = [0u8; TAG_BYTES];
    words_to_bytes_le(&tag_words, &mut tag);
    tag
}

/// Schwaemm256-256 encrypt
pub fn encrypt(
    key: &[u8; KEY_BYTES],
    nonce: &[u8; NONCE_BYTES],
    plaintext: &[u8],
    aad: &[u8],
) -> (Vec<u8>, [u8; TAG_BYTES]) {
    let mut state = initialize(key, nonce);
    process_assoc_data(&mut state, aad);
    let ciphertext = process_plaintext(&mut state, plaintext);
    finalize(&mut state, key);
    let tag = generate_tag(&state);

    (ciphertext, tag)
}

/// Process ciphertext (decryption)
fn process_ciphertext(state: &mut SparkleState, ciphertext: &[u8]) -> Vec<u8> {
    if ciphertext.is_empty() {
        return Vec::new();
    }

    let mut plaintext = Vec::with_capacity(ciphertext.len());
    let mut offset = 0;

    // Main decryption loop
    while ciphertext.len() - offset > RATE_BYTES {
        let mut pt_block = vec![0u8; RATE_BYTES];
        rho_whi_dec(state, &mut pt_block, &ciphertext[offset..offset + RATE_BYTES]);
        plaintext.extend_from_slice(&pt_block);
        sparkle_state(state, SPARKLE_STEPS_SLIM);
        offset += RATE_BYTES;
    }

    // Decryption of last block
    let remaining = &ciphertext[offset..];
    let const_val = if remaining.len() < RATE_BYTES {
        CONST_M2
    } else {
        CONST_M3
    };
    state.y[7] ^= const_val; // XOR to last y-word

    let mut pt_block = vec![0u8; remaining.len()];
    rho_whi_dec(state, &mut pt_block, remaining);
    plaintext.extend_from_slice(&pt_block);
    sparkle_state(state, SPARKLE_STEPS_BIG);

    plaintext
}

/// Verify authentication tag (constant-time comparison)
fn verify_tag(state: &SparkleState, tag: &[u8; TAG_BYTES]) -> bool {
    let mut tag_words = Vec::new();
    for i in 0..4 {
        tag_words.push(state.x[RATE_BRANS + i]);
        tag_words.push(state.y[RATE_BRANS + i]);
    }

    let mut computed_tag = [0u8; TAG_BYTES];
    words_to_bytes_le(&tag_words, &mut computed_tag);

    // Constant-time comparison
    let mut diff = 0u8;
    for i in 0..TAG_BYTES {
        diff |= computed_tag[i] ^ tag[i];
    }

    diff == 0
}

/// Schwaemm256-256 decrypt
pub fn decrypt(
    key: &[u8; KEY_BYTES],
    nonce: &[u8; NONCE_BYTES],
    ciphertext: &[u8],
    tag: &[u8; TAG_BYTES],
    aad: &[u8],
) -> Result<Vec<u8>, &'static str> {
    let mut state = initialize(key, nonce);
    process_assoc_data(&mut state, aad);
    let plaintext = process_ciphertext(&mut state, ciphertext);
    finalize(&mut state, key);

    if !verify_tag(&state, tag) {
        return Err("authentication failed");
    }

    Ok(plaintext)
}

#[cfg(test)]
mod tests {
    use super::*;

    // Helper to convert hex string to bytes
    fn hex_to_bytes(hex: &str) -> Vec<u8> {
        (0..hex.len())
            .step_by(2)
            .map(|i| u8::from_str_radix(&hex[i..i + 2], 16).unwrap())
            .collect()
    }

    #[test]
    fn test_nist_kat_count_1_v2() {
        // NIST KAT Test Count 1: Empty plaintext, empty AAD
        let key_hex = "000102030405060708090A0B0C0D0E0F101112131415161718191A1B1C1D1E1F";
        let nonce_hex = "000102030405060708090A0B0C0D0E0F101112131415161718191A1B1C1D1E1F";
        let expected_tag_hex = "1E41C39049501061A480341DC8551F3CCE171900EB8F90BA5C54B2A7CC2BFDF2";

        let key: [u8; 32] = hex_to_bytes(key_hex).try_into().unwrap();
        let nonce: [u8; 32] = hex_to_bytes(nonce_hex).try_into().unwrap();
        let plaintext = b"";
        let aad = b"";

        let (ciphertext, tag) = encrypt(&key, &nonce, plaintext, aad);
        let expected_tag = hex_to_bytes(expected_tag_hex);

        eprintln!("Generated tag: {:02x?}", tag);
        eprintln!("Expected tag:  {:02x?}", expected_tag.as_slice());

        // Empty plaintext should produce empty ciphertext
        assert_eq!(ciphertext.len(), 0, "Ciphertext should be empty");

        // Tag should match NIST test vector
        assert_eq!(tag.to_vec(), expected_tag, "Tag mismatch for KAT Count 1");
    }

    #[test]
    fn test_nist_kat_count_2_v2() {
        // NIST KAT Test Count 2: Empty plaintext, 1 byte AAD
        let key_hex = "000102030405060708090A0B0C0D0E0F101112131415161718191A1B1C1D1E1F";
        let nonce_hex = "000102030405060708090A0B0C0D0E0F101112131415161718191A1B1C1D1E1F";
        let aad_hex = "00";
        let expected_tag_hex = "6AF0F211BC7FF4186EEA03D37025F294036BE6E90970713E5B5A630FFF07DCBE";

        let key: [u8; 32] = hex_to_bytes(key_hex).try_into().unwrap();
        let nonce: [u8; 32] = hex_to_bytes(nonce_hex).try_into().unwrap();
        let aad = hex_to_bytes(aad_hex);
        let plaintext = b"";

        let (ciphertext, tag) = encrypt(&key, &nonce, plaintext, &aad);
        let expected_tag = hex_to_bytes(expected_tag_hex);

        assert_eq!(ciphertext.len(), 0);
        assert_eq!(tag.to_vec(), expected_tag, "Tag mismatch for KAT Count 2");
    }

    #[test]
    fn test_nist_kat_count_34_v2() {
        // NIST KAT Test Count 34: 1 byte plaintext, no AAD
        let key_hex = "000102030405060708090A0B0C0D0E0F101112131415161718191A1B1C1D1E1F";
        let nonce_hex = "000102030405060708090A0B0C0D0E0F101112131415161718191A1B1C1D1E1F";
        let pt_hex = "00";
        let expected_ct_tag_hex = "BBE3CED9AB9967846E9F39911BEBA2FFC4585C560043E4381E5FDAF8789265D791";

        let key: [u8; 32] = hex_to_bytes(key_hex).try_into().unwrap();
        let nonce: [u8; 32] = hex_to_bytes(nonce_hex).try_into().unwrap();
        let plaintext = hex_to_bytes(pt_hex);
        let aad = b"";

        let (ciphertext, tag) = encrypt(&key, &nonce, &plaintext, aad);

        // Expected output is CT || TAG (1 byte CT + 32 byte tag)
        let expected_full = hex_to_bytes(expected_ct_tag_hex);
        let expected_ct = &expected_full[..1];
        let expected_tag = &expected_full[1..];

        assert_eq!(ciphertext.as_slice(), expected_ct, "Ciphertext mismatch for KAT Count 34");
        assert_eq!(tag.as_slice(), expected_tag, "Tag mismatch for KAT Count 34");
    }

    #[test]
    fn test_nist_kat_count_1057_v2() {
        // NIST KAT Test Count 1057: 32 bytes plaintext (full block), no AAD
        let key_hex = "000102030405060708090A0B0C0D0E0F101112131415161718191A1B1C1D1E1F";
        let nonce_hex = "000102030405060708090A0B0C0D0E0F101112131415161718191A1B1C1D1E1F";
        let pt_hex = "000102030405060708090A0B0C0D0E0F101112131415161718191A1B1C1D1E1F";
        let expected_ct_tag_hex = "BB5918195DC5D4D944594A7B63D6460140BE022EFB65D13C16FB50A48F224B697E6B81DCA1366D43EE20B152AD39CEFCB6103D3EC26A1DC5277B117ADA1ED1BB";

        let key: [u8; 32] = hex_to_bytes(key_hex).try_into().unwrap();
        let nonce: [u8; 32] = hex_to_bytes(nonce_hex).try_into().unwrap();
        let plaintext = hex_to_bytes(pt_hex);
        let aad = b"";

        let (ciphertext, tag) = encrypt(&key, &nonce, &plaintext, aad);

        // Expected output is CT || TAG (32 byte CT + 32 byte tag)
        let expected_full = hex_to_bytes(expected_ct_tag_hex);
        let expected_ct = &expected_full[..32];
        let expected_tag = &expected_full[32..];

        assert_eq!(ciphertext.as_slice(), expected_ct, "Ciphertext mismatch for KAT Count 1057");
        assert_eq!(tag.as_slice(), expected_tag, "Tag mismatch for KAT Count 1057");
    }

    #[test]
    fn test_encrypt_decrypt_roundtrip() {
        let key = [0x42u8; KEY_BYTES];
        let nonce = [0x13u8; NONCE_BYTES];
        let plaintext = b"Hello, Schwaemm256-256! This is a test message for encrypt/decrypt roundtrip.";
        let aad = b"Additional authenticated data for testing";

        // Encrypt
        let (ciphertext, tag) = encrypt(&key, &nonce, plaintext, aad);

        // Verify ciphertext is different from plaintext
        assert_ne!(&ciphertext[..], &plaintext[..]);

        // Decrypt
        let decrypted = decrypt(&key, &nonce, &ciphertext, &tag, aad).unwrap();

        // Verify decrypted matches original
        assert_eq!(&decrypted[..], &plaintext[..]);
    }

    #[test]
    fn test_decrypt_authentication_failure() {
        let key = [0x42u8; KEY_BYTES];
        let nonce = [0x13u8; NONCE_BYTES];
        let plaintext = b"Test message";
        let aad = b"AAD";

        // Encrypt
        let (ciphertext, mut tag) = encrypt(&key, &nonce, plaintext, aad);

        // Tamper with tag
        tag[0] ^= 1;

        // Decrypt should fail
        let result = decrypt(&key, &nonce, &ciphertext, &tag, aad);
        assert!(result.is_err());
        assert_eq!(result.unwrap_err(), "authentication failed");
    }
}
