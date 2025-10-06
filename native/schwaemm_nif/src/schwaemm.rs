/// Schwaemm256-256 AEAD implementation
///
/// Schwaemm256-256 parameters:
/// - Key: 256 bits (32 bytes)
/// - Nonce: 256 bits (32 bytes)
/// - Tag: 256 bits (32 bytes)
/// - Rate: 256 bits (32 bytes / 8 words)
/// - Capacity: 256 bits (32 bytes / 8 words)
/// - State: 512 bits (64 bytes / 16 words) using Sparkle-512
/// - Sparkle steps: 8 (slim) and 12 (big)

use crate::sparkle::sparkle_512;

const RATE_WORDS: usize = 8;   // 256 bits
const CAP_WORDS: usize = 8;    // 256 bits
const STATE_WORDS: usize = 16; // 512 bits total

const RATE_BYTES: usize = 32;  // 256 bits
const TAG_BYTES: usize = 32;   // 256 bits
const KEY_BYTES: usize = 32;   // 256 bits
const NONCE_BYTES: usize = 32; // 256 bits

const SPARKLE_STEPS_SLIM: usize = 8;
const SPARKLE_STEPS_BIG: usize = 12;

// Domain separation constants
const CONST_A0: u32 = 0x00000000;
const CONST_A1: u32 = 0x01000000;
const CONST_M2: u32 = 0x02000000;
const CONST_M3: u32 = 0x03000000;

/// Convert bytes to u32 words (little-endian)
#[inline]
fn bytes_to_words(bytes: &[u8], words: &mut [u32]) {
    for (i, chunk) in bytes.chunks(4).enumerate() {
        if i < words.len() {
            let mut buf = [0u8; 4];
            buf[..chunk.len()].copy_from_slice(chunk);
            words[i] = u32::from_le_bytes(buf);
        }
    }
}

/// Convert u32 words to bytes (little-endian)
#[inline]
fn words_to_bytes(words: &[u32], bytes: &mut [u8]) {
    for (i, &word) in words.iter().enumerate() {
        let word_bytes = word.to_le_bytes();
        let start = i * 4;
        let end = (start + 4).min(bytes.len());
        bytes[start..end].copy_from_slice(&word_bytes[..(end - start)]);
    }
}

/// Schwaemm256-256 encrypt
pub fn encrypt(
    key: &[u8; KEY_BYTES],
    nonce: &[u8; NONCE_BYTES],
    plaintext: &[u8],
    aad: &[u8],
) -> (Vec<u8>, [u8; TAG_BYTES]) {
    let mut state = [0u32; STATE_WORDS];

    // Initialize: Load nonce into rate, key into capacity
    bytes_to_words(nonce, &mut state[0..RATE_WORDS]);
    bytes_to_words(key, &mut state[RATE_WORDS..STATE_WORDS]);

    // Process associated data
    if !aad.is_empty() {
        for chunk in aad.chunks(RATE_BYTES) {
            // XOR AAD into rate
            let mut temp = [0u32; RATE_WORDS];
            bytes_to_words(chunk, &mut temp);
            for i in 0..RATE_WORDS {
                state[i] ^= temp[i];
            }

            // Add domain separation for AAD
            if chunk.len() < RATE_BYTES {
                state[0] ^= CONST_A0 | (1 << 24); // Partial block
                state[1] ^= (chunk.len() as u32) << 24;
            } else {
                state[0] ^= CONST_A1; // Full block
            }

            // Apply Sparkle permutation (slim for AAD)
            sparkle_512(&mut state, SPARKLE_STEPS_SLIM);
        }
    }

    // Process plaintext
    let mut ciphertext = Vec::with_capacity(plaintext.len());
    if !plaintext.is_empty() {
        for chunk in plaintext.chunks(RATE_BYTES) {
            // XOR plaintext into rate and extract ciphertext
            let mut pt_words = [0u32; RATE_WORDS];
            bytes_to_words(chunk, &mut pt_words);

            let mut ct_block = [0u8; RATE_BYTES];
            for i in 0..RATE_WORDS {
                let ct_word = state[i] ^ pt_words[i];
                ct_block[i * 4..(i + 1) * 4].copy_from_slice(&ct_word.to_le_bytes());
                state[i] ^= pt_words[i]; // Update state with plaintext
            }
            ciphertext.extend_from_slice(&ct_block[..chunk.len()]);

            // Add domain separation for message
            if chunk.len() < RATE_BYTES {
                state[0] ^= CONST_M2 | (1 << 24); // Partial block
                state[1] ^= (chunk.len() as u32) << 24;
            } else {
                state[0] ^= CONST_M3; // Full block
            }

            // Apply Sparkle permutation (big for message)
            sparkle_512(&mut state, SPARKLE_STEPS_BIG);
        }
    }

    // Finalization: XOR key into capacity, then apply permutation
    for i in 0..CAP_WORDS {
        state[RATE_WORDS + i] ^= bytes_to_word(&key[i * 4..(i + 1) * 4]);
    }
    sparkle_512(&mut state, SPARKLE_STEPS_BIG);

    // Extract tag from rate
    let mut tag = [0u8; TAG_BYTES];
    words_to_bytes(&state[0..RATE_WORDS], &mut tag);

    eprintln!("Final state (rate): {:08x?}", &state[0..RATE_WORDS]);
    eprintln!("Extracted tag: {:02x?}", &tag);

    (ciphertext, tag)
}

// Helper to convert 4 bytes to u32
#[inline]
fn bytes_to_word(bytes: &[u8]) -> u32 {
    let mut buf = [0u8; 4];
    buf[..bytes.len().min(4)].copy_from_slice(&bytes[..bytes.len().min(4)]);
    u32::from_le_bytes(buf)
}

/// Schwaemm256-256 decrypt
pub fn decrypt(
    key: &[u8; KEY_BYTES],
    nonce: &[u8; NONCE_BYTES],
    ciphertext: &[u8],
    tag: &[u8; TAG_BYTES],
    aad: &[u8],
) -> Result<Vec<u8>, &'static str> {
    let mut state = [0u32; STATE_WORDS];

    // Initialize: Load nonce into rate, key into capacity
    bytes_to_words(nonce, &mut state[0..RATE_WORDS]);
    bytes_to_words(key, &mut state[RATE_WORDS..STATE_WORDS]);

    // Process associated data (same as encryption)
    if !aad.is_empty() {
        for chunk in aad.chunks(RATE_BYTES) {
            let mut temp = [0u32; RATE_WORDS];
            bytes_to_words(chunk, &mut temp);
            for i in 0..RATE_WORDS {
                state[i] ^= temp[i];
            }

            if chunk.len() < RATE_BYTES {
                state[0] ^= CONST_A0 | (1 << 24);
                state[1] ^= (chunk.len() as u32) << 24;
            } else {
                state[0] ^= CONST_A1;
            }

            sparkle_512(&mut state, SPARKLE_STEPS_SLIM);
        }
    }

    // Process ciphertext
    let mut plaintext = Vec::with_capacity(ciphertext.len());
    for chunk in ciphertext.chunks(RATE_BYTES) {
        // Convert ciphertext chunk to words
        let mut ct_words = [0u32; RATE_WORDS];
        bytes_to_words(chunk, &mut ct_words);

        // XOR with state to get plaintext, update state with ciphertext
        let mut pt_block = [0u8; RATE_BYTES];
        for i in 0..RATE_WORDS {
            let pt_word = state[i] ^ ct_words[i];
            pt_block[i * 4..(i + 1) * 4].copy_from_slice(&pt_word.to_le_bytes());
            state[i] = ct_words[i];
        }
        plaintext.extend_from_slice(&pt_block[..chunk.len()]);

        // Add domain separation
        if chunk.len() < RATE_BYTES {
            state[0] ^= CONST_M2 | (1 << 24);
            state[1] ^= (chunk.len() as u32) << 24;
        } else {
            state[0] ^= CONST_M3;
        }

        sparkle_512(&mut state, SPARKLE_STEPS_BIG);
    }

    // Finalization: XOR key into capacity, then apply permutation (same as encrypt)
    for i in 0..CAP_WORDS {
        state[RATE_WORDS + i] ^= bytes_to_word(&key[i * 4..(i + 1) * 4]);
    }
    sparkle_512(&mut state, SPARKLE_STEPS_BIG);

    // Verify tag
    let mut computed_tag = [0u8; TAG_BYTES];
    words_to_bytes(&state[0..RATE_WORDS], &mut computed_tag);

    // Constant-time comparison
    let mut diff = 0u8;
    for i in 0..TAG_BYTES {
        diff |= computed_tag[i] ^ tag[i];
    }

    if diff != 0 {
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
    fn test_nist_kat_count_1() {
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

        // Empty plaintext should produce empty ciphertext
        assert_eq!(ciphertext.len(), 0, "Ciphertext should be empty");

        // Tag should match NIST test vector
        assert_eq!(tag.to_vec(), expected_tag, "Tag mismatch for KAT Count 1");
    }

    #[test]
    fn test_nist_kat_count_2() {
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
    fn test_nist_kat_count_3() {
        // NIST KAT Test Count 3: Empty plaintext, 2 bytes AAD
        let key_hex = "000102030405060708090A0B0C0D0E0F101112131415161718191A1B1C1D1E1F";
        let nonce_hex = "000102030405060708090A0B0C0D0E0F101112131415161718191A1B1C1D1E1F";
        let aad_hex = "0001";
        let expected_tag_hex = "90B680DF1FDEE153D1310A538AB7F4D0127CC4FA61A012E238417F3BB74DF6D4";

        let key: [u8; 32] = hex_to_bytes(key_hex).try_into().unwrap();
        let nonce: [u8; 32] = hex_to_bytes(nonce_hex).try_into().unwrap();
        let aad = hex_to_bytes(aad_hex);
        let plaintext = b"";

        let (ciphertext, tag) = encrypt(&key, &nonce, plaintext, &aad);
        let expected_tag = hex_to_bytes(expected_tag_hex);

        assert_eq!(ciphertext.len(), 0);
        assert_eq!(tag.to_vec(), expected_tag, "Tag mismatch for KAT Count 3");
    }

    #[test]
    fn test_encrypt_decrypt_empty() {
        let key = [0u8; KEY_BYTES];
        let nonce = [0u8; NONCE_BYTES];
        let plaintext = b"";
        let aad = b"";

        let (ct, tag) = encrypt(&key, &nonce, plaintext, aad);
        let pt = decrypt(&key, &nonce, &ct, &tag, aad).unwrap();

        assert_eq!(pt, plaintext);
    }

    #[test]
    fn test_encrypt_decrypt_basic() {
        let key = [1u8; KEY_BYTES];
        let nonce = [2u8; NONCE_BYTES];
        let plaintext = b"Hello, Schwaemm!";
        let aad = b"additional data";

        let (ct, tag) = encrypt(&key, &nonce, plaintext, aad);

        eprintln!("Plaintext: {:02x?}", plaintext);
        eprintln!("Ciphertext: {:02x?}", &ct);
        eprintln!("Tag: {:02x?}", &tag);

        let pt = decrypt(&key, &nonce, &ct, &tag, aad).unwrap();

        assert_eq!(&pt[..], plaintext);
        assert_ne!(&ct[..], plaintext); // Ciphertext should differ
    }

    #[test]
    fn test_authentication_failure() {
        let key = [1u8; KEY_BYTES];
        let nonce = [2u8; NONCE_BYTES];
        let plaintext = b"test";
        let aad = b"aad";

        let (ct, mut tag) = encrypt(&key, &nonce, plaintext, aad);
        tag[0] ^= 1; // Tamper with tag

        let result = decrypt(&key, &nonce, &ct, &tag, aad);
        assert!(result.is_err());
    }

    #[test]
    fn test_deterministic() {
        let key = [3u8; KEY_BYTES];
        let nonce = [4u8; NONCE_BYTES];
        let plaintext = b"deterministic test";
        let aad = b"";

        let (ct1, tag1) = encrypt(&key, &nonce, plaintext, aad);
        let (ct2, tag2) = encrypt(&key, &nonce, plaintext, aad);

        assert_eq!(ct1, ct2);
        assert_eq!(tag1, tag2);
    }
}
