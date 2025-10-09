use rustler::{Env, Binary, Error, OwnedBinary};

rustler::init!("Elixir.GitFoil.Native.DeoxysNif");

/// Deoxys-II-256 Encryption
///
/// Parameters:
/// - key: 32 bytes
/// - nonce: 15 bytes (120 bits - Deoxys-II specification)
/// - plaintext: variable length
/// - aad: variable length (additional authenticated data)
///
/// Returns:
/// - Ok({ciphertext, tag}) where tag is 16 bytes
/// - Err for errors
#[rustler::nif]
fn encrypt<'a>(
    env: Env<'a>,
    key: Binary,
    nonce: Binary,
    plaintext: Binary,
    aad: Binary,
) -> Result<(Binary<'a>, Binary<'a>), Error> {
    // Validate key length (32 bytes = 256 bits)
    if key.len() != 32 {
        return Err(Error::BadArg);
    }

    // Validate nonce length (15 bytes = 120 bits, Deoxys-II spec)
    if nonce.len() != 15 {
        return Err(Error::BadArg);
    }

    // Use the deoxys crate's AEAD trait implementation
    use deoxys::DeoxysII256;
    use deoxys::aead::{Aead, KeyInit, Payload};

    // Convert to GenericArray types
    let key_array = deoxys::aead::generic_array::GenericArray::from_slice(key.as_slice());
    let nonce_array = deoxys::aead::generic_array::GenericArray::from_slice(nonce.as_slice());

    // Create cipher
    let cipher = DeoxysII256::new(key_array);

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

/// Deoxys-II-256 Decryption
///
/// Parameters:
/// - key: 32 bytes
/// - nonce: 15 bytes (120 bits - Deoxys-II specification)
/// - ciphertext: variable length
/// - tag: 16 bytes (authentication tag)
/// - aad: variable length (additional authenticated data)
///
/// Returns:
/// - Ok(plaintext)
/// - Err if authentication fails
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
    if key.len() != 32 {
        return Err(Error::BadArg);
    }
    if nonce.len() != 15 {
        return Err(Error::BadArg);
    }
    if tag.len() != 16 {
        return Err(Error::BadArg);
    }

    // Use the deoxys crate's AEAD trait implementation
    use deoxys::DeoxysII256;
    use deoxys::aead::{Aead, KeyInit, Payload};

    // Convert to GenericArray types
    let key_array = deoxys::aead::generic_array::GenericArray::from_slice(key.as_slice());
    let nonce_array = deoxys::aead::generic_array::GenericArray::from_slice(nonce.as_slice());

    // Reconstruct ciphertext with tag
    let mut ciphertext_with_tag = Vec::with_capacity(ciphertext.len() + 16);
    ciphertext_with_tag.extend_from_slice(ciphertext.as_slice());
    ciphertext_with_tag.extend_from_slice(tag.as_slice());

    // Create cipher
    let cipher = DeoxysII256::new(key_array);

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
