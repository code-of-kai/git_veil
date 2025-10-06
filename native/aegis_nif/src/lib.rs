use rustler::{Env, Binary, Error, OwnedBinary};

rustler::init!("Elixir.GitVeil.Native.AegisNif");

/// AEGIS-256 Encryption
///
/// Parameters:
/// - key: 32 bytes
/// - nonce: 32 bytes
/// - plaintext: variable length
/// - aad: variable length (additional authenticated data)
///
/// Returns:
/// - Ok({ciphertext, tag}) where tag is 32 bytes
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

    // Validate nonce length (32 bytes = 256 bits)
    if nonce.len() != 32 {
        return Err(Error::BadArg);
    }

    // Use the aegis crate's native API
    use aegis::aegis256::Aegis256;

    // Create key and nonce arrays
    let key_array: &[u8; 32] = key.as_slice().try_into()
        .map_err(|_| Error::BadArg)?;
    let nonce_array: &[u8; 32] = nonce.as_slice().try_into()
        .map_err(|_| Error::BadArg)?;

    // Create cipher with key and nonce (32-byte tag)
    let cipher: Aegis256<32> = Aegis256::new(key_array, nonce_array);

    // Encrypt
    let (ciphertext, tag) = cipher.encrypt(plaintext.as_slice(), aad.as_slice());

    // Copy to Elixir binaries
    let mut ciphertext_binary = OwnedBinary::new(ciphertext.len()).unwrap();
    ciphertext_binary.as_mut_slice().copy_from_slice(&ciphertext);

    let mut tag_binary = OwnedBinary::new(tag.len()).unwrap();
    tag_binary.as_mut_slice().copy_from_slice(&tag);

    Ok((
        ciphertext_binary.release(env),
        tag_binary.release(env),
    ))
}

/// AEGIS-256 Decryption
///
/// Parameters:
/// - key: 32 bytes
/// - nonce: 32 bytes
/// - ciphertext: variable length
/// - tag: 32 bytes (authentication tag)
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
    if nonce.len() != 32 {
        return Err(Error::BadArg);
    }
    if tag.len() != 32 {
        return Err(Error::BadArg);
    }

    // Use the aegis crate's native API
    use aegis::aegis256::Aegis256;

    // Create key and nonce arrays
    let key_array: &[u8; 32] = key.as_slice().try_into()
        .map_err(|_| Error::BadArg)?;
    let nonce_array: &[u8; 32] = nonce.as_slice().try_into()
        .map_err(|_| Error::BadArg)?;

    // Create cipher with key and nonce (32-byte tag)
    let cipher: Aegis256<32> = Aegis256::new(key_array, nonce_array);

    // Decrypt and verify
    let tag_array: &[u8; 32] = tag.as_slice().try_into()
        .map_err(|_| Error::BadArg)?;
    let plaintext = cipher
        .decrypt(ciphertext.as_slice(), tag_array, aad.as_slice())
        .map_err(|_| Error::RaiseTerm(Box::new("authentication failed")))?;

    // Copy to Elixir binary
    let mut plaintext_binary = OwnedBinary::new(plaintext.len()).unwrap();
    plaintext_binary.as_mut_slice().copy_from_slice(&plaintext);

    Ok(plaintext_binary.release(env))
}
