defmodule GitFoil.Core.Types do
  @moduledoc """
  Core domain types with zero I/O dependencies.

  All types are plain Elixir structs with no behavior.
  """

  defmodule EncryptionContext do
    @moduledoc """
    Context for encryption operations.

    Contains the file path and master key needed for deterministic encryption.
    """

    @enforce_keys [:file_path, :master_key]
    defstruct [:file_path, :master_key, :base_iv]

    @type t :: %__MODULE__{
      file_path: String.t(),
      master_key: binary(),
      base_iv: binary() | nil
    }

    @spec new(String.t(), binary()) :: t()
    def new(file_path, master_key) when is_binary(file_path) and byte_size(master_key) == 64 do
      %__MODULE__{file_path: file_path, master_key: master_key}
    end
  end

  defmodule FileKeys do
    @moduledoc """
    Three independent 32-byte keys derived for a specific file.

    Each layer of encryption uses its own key.
    """

    @enforce_keys [:layer1_key, :layer2_key, :layer3_key]
    defstruct [:layer1_key, :layer2_key, :layer3_key]

    @type t :: %__MODULE__{
      layer1_key: binary(),
      layer2_key: binary(),
      layer3_key: binary()
    }

    @spec new(binary(), binary(), binary()) :: t()
    def new(layer1, layer2, layer3)
      when byte_size(layer1) == 32 and byte_size(layer2) == 32 and byte_size(layer3) == 32 do
      %__MODULE__{layer1_key: layer1, layer2_key: layer2, layer3_key: layer3}
    end
  end

  defmodule EncryptionResult do
    @moduledoc """
    Result of triple-layer encryption containing ciphertext and all metadata.
    """

    @enforce_keys [:ciphertext, :layer1_iv, :layer1_tag, :layer2_iv, :layer2_tag, :layer3_iv, :layer3_tag]
    defstruct [:ciphertext, :layer1_iv, :layer1_tag, :layer2_iv, :layer2_tag, :layer3_iv, :layer3_tag]

    @type t :: %__MODULE__{
      ciphertext: binary(),
      layer1_iv: binary(),
      layer1_tag: binary(),
      layer2_iv: binary(),
      layer2_tag: binary(),
      layer3_iv: binary(),
      layer3_tag: binary()
    }

    @spec new(binary(), binary(), binary(), binary(), binary(), binary(), binary()) :: t()
    def new(ciphertext, iv1, tag1, iv2, tag2, iv3, tag3) do
      %__MODULE__{
        ciphertext: ciphertext,
        layer1_iv: iv1,
        layer1_tag: tag1,
        layer2_iv: iv2,
        layer2_tag: tag2,
        layer3_iv: iv3,
        layer3_tag: tag3
      }
    end
  end

  defmodule Keypair do
    @moduledoc """
    Hybrid post-quantum keypair.

    **NOW WITH REAL POST-QUANTUM KEYS:**
    - pq_public/pq_secret: Real Kyber1024 (ML-KEM-1024) keys from pqclean NIF
    - classical_public/classical_secret: Placeholder (will be X25519 in future)

    Sizes:
    - classical keys: 32 bytes each
    - pq_public: 1,568 bytes (Kyber1024)
    - pq_secret: 3,168 bytes (Kyber1024)
    """

    @enforce_keys [:classical_public, :classical_secret, :pq_public, :pq_secret]
    defstruct [:classical_public, :classical_secret, :pq_public, :pq_secret]

    @type t :: %__MODULE__{
      classical_public: binary(),
      classical_secret: binary(),
      pq_public: binary(),
      pq_secret: binary()
    }
  end

  defmodule EncryptionKey do
    @moduledoc """
    Master encryption key for file encryption.

    This key is derived from the master keypair and used to derive
    layer-specific keys via HKDF.
    """

    @enforce_keys [:key]
    defstruct [:key]

    @type t :: %__MODULE__{
      key: binary()
    }

    @spec new(binary()) :: t()
    def new(key) when byte_size(key) == 32 do
      %__MODULE__{key: key}
    end
  end

  defmodule DerivedKeys do
    @moduledoc """
    Six independent keys derived from master key for 6-layer encryption.

    Each layer of encryption uses its own derived key for maximum isolation.

    **Key sizes (v3.0):**
    - layer1_key: 32 bytes (AES-256-GCM)
    - layer2_key: 32 bytes (AEGIS-256)
    - layer3_key: 32 bytes (Schwaemm256-256)
    - layer4_key: 32 bytes (Deoxys-II-256)
    - layer5_key: 16 bytes (Ascon-128a)
    - layer6_key: 32 bytes (ChaCha20-Poly1305)

    Total: 1,408 bits → 704 bits post-quantum security
    """

    @enforce_keys [:layer1_key, :layer2_key, :layer3_key, :layer4_key, :layer5_key, :layer6_key]
    defstruct [:layer1_key, :layer2_key, :layer3_key, :layer4_key, :layer5_key, :layer6_key]

    @type t :: %__MODULE__{
      layer1_key: binary(),
      layer2_key: binary(),
      layer3_key: binary(),
      layer4_key: binary(),
      layer5_key: binary(),
      layer6_key: binary()
    }
  end

  defmodule EncryptedBlob do
    @moduledoc """
    Encrypted blob with version and authentication tags.

    **Wire format v3.0 (6-layer):**
    ```
    [version:1][tag1:16][tag2:32][tag3:32][tag4:16][tag5:16][tag6:16][ciphertext:variable]
    ```

    **Tag sizes:**
    - tag1: 16 bytes (AES-256-GCM)
    - tag2: 32 bytes (AEGIS-256)
    - tag3: 32 bytes (Schwaemm256-256)
    - tag4: 16 bytes (Deoxys-II-256)
    - tag5: 16 bytes (Ascon-128a)
    - tag6: 16 bytes (ChaCha20-Poly1305)

    Total overhead: 1 + 16 + 32 + 32 + 16 + 16 + 16 = 129 bytes per file
    """

    @enforce_keys [:version, :tag1, :tag2, :tag3, :tag4, :tag5, :tag6, :ciphertext]
    defstruct [:version, :tag1, :tag2, :tag3, :tag4, :tag5, :tag6, :ciphertext]

    @type t :: %__MODULE__{
      version: non_neg_integer(),
      tag1: binary(),
      tag2: binary(),
      tag3: binary(),
      tag4: binary(),
      tag5: binary(),
      tag6: binary(),
      ciphertext: binary()
    }
  end
end
