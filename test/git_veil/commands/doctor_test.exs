defmodule GitVeil.Commands.DoctorTest do
  use ExUnit.Case, async: false

  alias GitVeil.Adapters.{InMemoryKeyStorage, MockCrypto, OpenSSLCrypto}
  alias GitVeil.Commands.Doctor

  setup do
    # Start and initialize key storage for each test
    {:ok, _} = start_supervised(InMemoryKeyStorage)

    {:ok, keypair} = InMemoryKeyStorage.generate_keypair()
    :ok = InMemoryKeyStorage.save_keypair(keypair)

    :ok
  end

  describe "health check with all components working" do
    test "passes all checks with OpenSSL crypto" do
      {:ok, report} = Doctor.run(key_storage: InMemoryKeyStorage, crypto: OpenSSLCrypto)

      assert report.status == :healthy
      assert report.checks_passed == 5
      assert report.checks_failed == 0
    end

    test "passes all checks with Mock crypto" do
      {:ok, report} = Doctor.run(key_storage: InMemoryKeyStorage, crypto: MockCrypto)

      assert report.status == :healthy
      assert report.checks_passed == 5
      assert report.checks_failed == 0
    end

    test "verbose mode includes detailed messages" do
      {:ok, report} = Doctor.run(key_storage: InMemoryKeyStorage, crypto: OpenSSLCrypto, verbose: true)

      assert Map.has_key?(report, :details)
      assert is_list(report.details)
      assert length(report.details) == 5

      # Check that each check has a message
      Enum.each(report.details, fn {_name, message} ->
        assert is_binary(message)
        assert String.length(message) > 0
      end)
    end
  end

  describe "health check with key storage not initialized" do
    test "fails key storage check when not initialized" do
      # Stop and restart without initializing
      stop_supervised(InMemoryKeyStorage)
      {:ok, _} = start_supervised(InMemoryKeyStorage)

      {:error, failures} = Doctor.run(key_storage: InMemoryKeyStorage, crypto: OpenSSLCrypto)

      assert length(failures) > 0

      # Should have at least key_storage and encryption_engine failures
      failure_names = Enum.map(failures, fn {name, _reason} -> name end)
      assert :key_storage in failure_names
      assert :encryption_engine in failure_names
    end
  end

  describe "individual checks" do
    test "erlang_crypto check verifies required ciphers" do
      {:ok, report} = Doctor.run(key_storage: InMemoryKeyStorage, crypto: OpenSSLCrypto, verbose: true)

      erlang_crypto_check = Enum.find(report.details, fn {name, _} -> name == :erlang_crypto end)
      {_name, message} = erlang_crypto_check

      assert message =~ "required ciphers available"
      assert message =~ "aes_256_gcm"
      assert message =~ "chacha20_poly1305"
    end

    test "key_storage check verifies master key size" do
      {:ok, report} = Doctor.run(key_storage: InMemoryKeyStorage, crypto: OpenSSLCrypto, verbose: true)

      key_storage_check = Enum.find(report.details, fn {name, _} -> name == :key_storage end)
      {_name, message} = key_storage_check

      assert message =~ "64-byte master key"
    end

    test "crypto_provider check tests both algorithms" do
      {:ok, report} = Doctor.run(key_storage: InMemoryKeyStorage, crypto: OpenSSLCrypto, verbose: true)

      crypto_check = Enum.find(report.details, fn {name, _} -> name == :crypto_provider end)
      {_name, message} = crypto_check

      assert message =~ "working correctly"
    end

    test "encryption_engine check tests full pipeline" do
      {:ok, report} = Doctor.run(key_storage: InMemoryKeyStorage, crypto: OpenSSLCrypto, verbose: true)

      engine_check = Enum.find(report.details, fn {name, _} -> name == :encryption_engine end)
      {_name, message} = engine_check

      assert message =~ "round-trip successful"
    end

    test "key_derivation check verifies key and IV sizes" do
      {:ok, report} = Doctor.run(key_storage: InMemoryKeyStorage, crypto: OpenSSLCrypto, verbose: true)

      kdf_check = Enum.find(report.details, fn {name, _} -> name == :key_derivation end)
      {_name, message} = kdf_check

      assert message =~ "correct key and IV sizes"
    end
  end

  describe "report formatting" do
    test "formats successful report" do
      {:ok, report} = Doctor.run(key_storage: InMemoryKeyStorage, crypto: OpenSSLCrypto)

      formatted = Doctor.format_report(report)

      assert formatted =~ "GitVeil Health Check"
      assert formatted =~ "Checks passed: 5"
      assert formatted =~ "Checks failed: 0"
    end

    test "formats verbose report with details" do
      {:ok, report} = Doctor.run(key_storage: InMemoryKeyStorage, crypto: OpenSSLCrypto, verbose: true)

      formatted = Doctor.format_report(report)

      assert formatted =~ "GitVeil Health Check"
      assert formatted =~ "Details:"
      assert formatted =~ "erlang_crypto"
      assert formatted =~ "key_storage"
      assert formatted =~ "crypto_provider"
    end

    test "formats failure report" do
      # Stop and restart without initializing
      stop_supervised(InMemoryKeyStorage)
      {:ok, _} = start_supervised(InMemoryKeyStorage)

      {:error, failures} = Doctor.run(key_storage: InMemoryKeyStorage, crypto: OpenSSLCrypto)

      formatted = Doctor.format_report({:error, failures})

      assert formatted =~ "Failures detected"
      assert formatted =~ "key_storage"
    end
  end

  describe "integration test - full system health" do
    test "verifies entire encryption stack is operational" do
      # This integration test exercises:
      # 1. Key storage (InMemoryKeyStorage)
      # 2. Crypto provider (OpenSSLCrypto)
      # 3. Key derivation (HKDF)
      # 4. Encryption engine (full pipeline)
      # 5. Triple cipher (all three layers)

      {:ok, report} = Doctor.run(
        key_storage: InMemoryKeyStorage,
        crypto: OpenSSLCrypto,
        verbose: true
      )

      # All checks should pass
      assert report.status == :healthy
      assert report.checks_passed == 5
      assert report.checks_failed == 0

      # Verify each component was checked
      check_names = Enum.map(report.details, fn {name, _} -> name end)
      assert :erlang_crypto in check_names
      assert :key_storage in check_names
      assert :crypto_provider in check_names
      assert :encryption_engine in check_names
      assert :key_derivation in check_names

      # Verify all messages indicate success
      Enum.each(report.details, fn {_name, message} ->
        assert message != ""
        # Should not contain error indicators
        refute message =~ "failed"
        refute message =~ "error"
        refute message =~ "missing"
      end)
    end

    test "works with mock crypto for fast testing" do
      {:ok, report} = Doctor.run(
        key_storage: InMemoryKeyStorage,
        crypto: MockCrypto,
        verbose: true
      )

      assert report.status == :healthy
      assert report.checks_passed == 5

      # Verify crypto provider check mentions MockCrypto
      crypto_check = Enum.find(report.details, fn {name, _} -> name == :crypto_provider end)
      {_name, message} = crypto_check

      assert message =~ "MockCrypto"
    end
  end
end
