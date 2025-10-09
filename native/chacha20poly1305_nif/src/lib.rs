use rustler::{Env, Binary, Error, OwnedBinary};

rustler::init!("Elixir.GitFoil.Native.ChaCha20Poly1305Nif");

/// ChaCha20-Poly1305 Encryption (IETF variant)
///
/// Parameters:
/// - key: 32 bytes (256 bits)
/// - nonce: 12 bytes (96 bits) - IETF standard
/// - plaintext: variable length
/// - aad: variable length (additional authenticated data)
///
/// Returns:
/// - Ok({ciphertext, tag}) where tag is 16 bytes (128 bits)
/// - Err for invalid parameters
#[rustler::nif]
fn encrypt<'a>(
    env: Env<'a>,
    key: Binary,
    nonce: Binary,
    plaintext: Binary,
    aad: Binary,
) -> Result<(Binary<'a>, Binary<'a>), Error> {
    use chacha20poly1305::{
        aead::{Aead, KeyInit, Payload},
        ChaCha20Poly1305,
    };

    // Validate key length (32 bytes = 256 bits)
    if key.len() != 32 {
        return Err(Error::BadArg);
    }

    // Validate nonce length (12 bytes = 96 bits for IETF variant)
    if nonce.len() != 12 {
        return Err(Error::BadArg);
    }

    // Convert to fixed-size arrays
    let key_array: &[u8; 32] = key.as_slice().try_into()
        .map_err(|_| Error::BadArg)?;
    let nonce_array: &[u8; 12] = nonce.as_slice().try_into()
        .map_err(|_| Error::BadArg)?;

    // Create cipher instance
    let cipher = ChaCha20Poly1305::new(key_array.into());

    // Prepare payload with AAD
    let payload = Payload {
        msg: plaintext.as_slice(),
        aad: aad.as_slice(),
    };

    // Encrypt (returns ciphertext with tag appended)
    let ciphertext_with_tag = cipher
        .encrypt(nonce_array.into(), payload)
        .map_err(|_| Error::RaiseTerm(Box::new("encryption failed")))?;

    // Split ciphertext and tag (tag is last 16 bytes)
    let tag_start = ciphertext_with_tag.len().saturating_sub(16);
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

/// ChaCha20-Poly1305 Decryption (IETF variant)
///
/// Parameters:
/// - key: 32 bytes (256 bits)
/// - nonce: 12 bytes (96 bits) - IETF standard
/// - ciphertext: variable length
/// - tag: 16 bytes (128 bits) - authentication tag
/// - aad: variable length (additional authenticated data)
///
/// Returns:
/// - Ok(plaintext)
/// - Err if authentication fails or parameters invalid
#[rustler::nif]
fn decrypt<'a>(
    env: Env<'a>,
    key: Binary,
    nonce: Binary,
    ciphertext: Binary,
    tag: Binary,
    aad: Binary,
) -> Result<Binary<'a>, Error> {
    use chacha20poly1305::{
        aead::{Aead, KeyInit, Payload},
        ChaCha20Poly1305,
    };

    // Validate input sizes
    if key.len() != 32 {
        return Err(Error::BadArg);
    }
    if nonce.len() != 12 {
        return Err(Error::BadArg);
    }
    if tag.len() != 16 {
        return Err(Error::BadArg);
    }

    // Convert to fixed-size arrays
    let key_array: &[u8; 32] = key.as_slice().try_into()
        .map_err(|_| Error::BadArg)?;
    let nonce_array: &[u8; 12] = nonce.as_slice().try_into()
        .map_err(|_| Error::BadArg)?;

    // Create cipher instance
    let cipher = ChaCha20Poly1305::new(key_array.into());

    // Combine ciphertext and tag (ChaCha20Poly1305 expects them together)
    let mut ciphertext_with_tag = Vec::with_capacity(ciphertext.len() + 16);
    ciphertext_with_tag.extend_from_slice(ciphertext.as_slice());
    ciphertext_with_tag.extend_from_slice(tag.as_slice());

    // Prepare payload with AAD
    let payload = Payload {
        msg: &ciphertext_with_tag,
        aad: aad.as_slice(),
    };

    // Decrypt and verify
    let plaintext = cipher
        .decrypt(nonce_array.into(), payload)
        .map_err(|_| Error::RaiseTerm(Box::new("authentication failed")))?;

    // Copy to Elixir binary
    let mut plaintext_binary = OwnedBinary::new(plaintext.len()).unwrap();
    plaintext_binary.as_mut_slice().copy_from_slice(&plaintext);

    Ok(plaintext_binary.release(env))
}
