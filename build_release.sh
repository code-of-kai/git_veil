#!/bin/bash
set -e

echo "Building GitFoil standalone binaries with Burrito..."
export PATH="/opt/homebrew/opt/zig@0.14/bin:$PATH"
export MIX_ENV=prod

# Clean previous builds
rm -rf burrito_out

# Build all targets
echo "Y" | mix release

# Show results
echo ""
echo "✅ Build complete! Binaries created:"
ls -lh burrito_out/

echo ""
echo "Testing macOS ARM64 binary..."
./burrito_out/git_foil_macos_arm64 --version && echo "✅ Binary works!" || echo "⚠️  Binary test failed"
