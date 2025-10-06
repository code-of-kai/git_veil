#!/bin/bash
set -e

# Installation script for git-veil
# This handles building and installing git-veil properly

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_PREFIX="${INSTALL_PREFIX:-/usr/local}"
BUILD_ENV="${BUILD_ENV:-dev}"

echo "🔨 Building git-veil..."
cd "$SCRIPT_DIR"
mix release --overwrite

echo ""
echo "📦 Installing git-veil to $INSTALL_PREFIX..."

# Remove old installation if it exists
if [ -L "$INSTALL_PREFIX/bin/git-veil" ]; then
    echo "   Removing old symlink..."
    sudo rm "$INSTALL_PREFIX/bin/git-veil"
fi

if [ -d "$INSTALL_PREFIX/git-veil" ]; then
    echo "   Removing old installation directory..."
    sudo rm -rf "$INSTALL_PREFIX/git-veil"
fi

# Copy new build to install location
echo "   Copying release to $INSTALL_PREFIX/git-veil..."
sudo cp -r "_build/$BUILD_ENV/rel/git_veil" "$INSTALL_PREFIX/git-veil"

# Create symlink
echo "   Creating symlink..."
sudo ln -s "$INSTALL_PREFIX/git-veil/bin/git-veil" "$INSTALL_PREFIX/bin/git-veil"

# Verify installation
echo ""
echo "✅ Installation complete!"
echo ""
git-veil --version
echo ""
echo "📍 Installed to: $INSTALL_PREFIX/git-veil"
echo "🔗 Symlinked at: $INSTALL_PREFIX/bin/git-veil"
