# GitFoil Scripts

This directory contains utility scripts for development, testing, and installation.

## Installation Scripts

- **`install.sh`** - Production installation script (escript build)
- **`install-dev.sh`** - Development installation script with Rust NIFs

## Build Scripts

- **`../build_release.sh`** - Burrito standalone binary builder (in project root)

## Test Scripts

- **`demo_ascon.exs`** - Ascon-128a encryption demonstration
- **`encrypt_real_file.exs`** - Real-world file encryption test
- **`test_chacha20_quick.exs`** - ChaCha20-Poly1305 quick test
- **`test_deterministic_encryption.exs`** - Deterministic encryption validation
- **`test_schwaemm_quick.exs`** - Schwaemm-256 quick test

## Usage

All `.exs` scripts can be run with:
```bash
mix run scripts/<script_name>.exs
```

Installation scripts should be run directly:
```bash
./scripts/install.sh
```
