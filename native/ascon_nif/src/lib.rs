//! Ascon-128a NIF for GitVeil
//!
//! Provides Ascon-128a AEAD encryption/decryption via Rustler NIF.
//!
//! **Algorithm:** Ascon-128a (NIST Lightweight Crypto winner)
//! - Key size: 128 bits (16 bytes)
//! - Nonce size: 128 bits (16 bytes)
//! - Tag size: 128 bits (16 bytes)
//!
//! **Security:**
//! - Post-quantum resistant design
//! - Authenticated encryption with associated data (AEAD)
//! - Constant-time operations (no timing leaks)

use ascon_aead::{
    aead::{Aead, KeyInit, Payload},
    Ascon128a,
};
use rustler::{Binary, Env, Error, OwnedBinary};

/// Initialize the NIF module
#[rustler::nif]
fn init() -> &'static str {
    "Ascon-128a NIF initialized"
}

/// Encrypts plaintext using Ascon-128a AEAD
///
/// ## Parameters
/// - key: 16-byte encryption key
/// - nonce: 16-byte nonce (must be unique per encryption)
/// - plaintext: Data to encrypt
/// - aad: Additional authenticated data (file path)
///
/// ## Returns
/// - Ok((ciphertext, tag)): Encrypted data + 16-byte authentication tag
/// - Err: Encryption failed
#[rustler::nif]
fn encrypt<'a>(
    env: Env<'a>,
    key: Binary,
    nonce: Binary,
    plaintext: Binary,
    aad: Binary,
) -> Result<(Binary<'a>, Binary<'a>), Error> {
    // Validate input sizes
    if key.len() != 16 {
        return Err(Error::BadArg);
    }
    if nonce.len() != 16 {
        return Err(Error::BadArg);
    }

    // Convert inputs to Ascon types (16-byte arrays)
    let key_array: &ascon_aead::aead::generic_array::GenericArray<u8, ascon_aead::aead::consts::U16> =
        ascon_aead::aead::generic_array::GenericArray::from_slice(key.as_slice());
    let nonce_array: &ascon_aead::aead::generic_array::GenericArray<u8, ascon_aead::aead::consts::U16> =
        ascon_aead::aead::generic_array::GenericArray::from_slice(nonce.as_slice());

    // Create cipher instance
    let cipher = Ascon128a::new(key_array);

    // Create payload with AAD
    let payload = Payload {
        msg: plaintext.as_slice(),
        aad: aad.as_slice(),
    };

    // Encrypt
    let ciphertext_with_tag = cipher
        .encrypt(nonce_array, payload)
        .map_err(|_| Error::RaiseTerm(Box::new("encryption failed")))?;

    // Split ciphertext and tag (last 16 bytes)
    let tag_start = ciphertext_with_tag.len() - 16;
    let ciphertext = &ciphertext_with_tag[..tag_start];
    let tag = &ciphertext_with_tag[tag_start..];

    // Copy to Elixir binaries
    let mut ciphertext_binary = OwnedBinary::new(ciphertext.len()).unwrap();
    ciphertext_binary.as_mut_slice().copy_from_slice(ciphertext);

    let mut tag_binary = OwnedBinary::new(16).unwrap();
    tag_binary.as_mut_slice().copy_from_slice(tag);

    Ok((
        ciphertext_binary.release(env),
        tag_binary.release(env),
    ))
}

/// Decrypts ciphertext using Ascon-128a AEAD
///
/// ## Parameters
/// - key: 16-byte encryption key
/// - nonce: 16-byte nonce (same as encryption)
/// - ciphertext: Encrypted data
/// - tag: 16-byte authentication tag
/// - aad: Additional authenticated data (file path, same as encryption)
///
/// ## Returns
/// - Ok(plaintext): Decrypted data (if authentication succeeds)
/// - Err: Decryption or authentication failed
#[rustler::nif]
fn decrypt<'a>(
    env: Env<'a>,
    key: Binary,
    nonce: Binary,
    ciphertext: Binary,
    tag: Binary,
    aad: Binary,
) -> Result<Binary<'a>, Error> {
    // Validate input sizes
    if key.len() != 16 {
        return Err(Error::BadArg);
    }
    if nonce.len() != 16 {
        return Err(Error::BadArg);
    }
    if tag.len() != 16 {
        return Err(Error::BadArg);
    }

    // Convert inputs to Ascon types (16-byte arrays)
    let key_array: &ascon_aead::aead::generic_array::GenericArray<u8, ascon_aead::aead::consts::U16> =
        ascon_aead::aead::generic_array::GenericArray::from_slice(key.as_slice());
    let nonce_array: &ascon_aead::aead::generic_array::GenericArray<u8, ascon_aead::aead::consts::U16> =
        ascon_aead::aead::generic_array::GenericArray::from_slice(nonce.as_slice());

    // Reconstruct ciphertext with tag (Ascon library expects them together)
    let mut ciphertext_with_tag = Vec::with_capacity(ciphertext.len() + 16);
    ciphertext_with_tag.extend_from_slice(ciphertext.as_slice());
    ciphertext_with_tag.extend_from_slice(tag.as_slice());

    // Create cipher instance
    let cipher = Ascon128a::new(key_array);

    // Create payload with AAD
    let payload = Payload {
        msg: &ciphertext_with_tag,
        aad: aad.as_slice(),
    };

    // Decrypt and verify
    let plaintext = cipher
        .decrypt(nonce_array, payload)
        .map_err(|_| Error::RaiseTerm(Box::new("authentication failed")))?;

    // Copy to Elixir binary
    let mut plaintext_binary = OwnedBinary::new(plaintext.len()).unwrap();
    plaintext_binary.as_mut_slice().copy_from_slice(&plaintext);

    Ok(plaintext_binary.release(env))
}

rustler::init!("Elixir.GitVeil.Native.AsconNif");
