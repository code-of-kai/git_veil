#!/bin/bash
set -e

# Installation script for git-foil
# This handles building and installing git-foil properly

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_PREFIX="${INSTALL_PREFIX:-/usr/local}"
BUILD_ENV="${BUILD_ENV:-dev}"

echo "🔨 Building git-foil..."
cd "$SCRIPT_DIR"
mix release --overwrite

echo ""
echo "📦 Installing git-foil to $INSTALL_PREFIX..."

# Remove old installation if it exists
if [ -L "$INSTALL_PREFIX/bin/git-foil" ]; then
    echo "   Removing old symlink..."
    sudo rm "$INSTALL_PREFIX/bin/git-foil"
fi

if [ -d "$INSTALL_PREFIX/git-foil" ]; then
    echo "   Removing old installation directory..."
    sudo rm -rf "$INSTALL_PREFIX/git-foil"
fi

# Copy new build to install location
echo "   Copying release to $INSTALL_PREFIX/git-foil..."
sudo cp -r "_build/$BUILD_ENV/rel/git_foil" "$INSTALL_PREFIX/git-foil"

# Create symlink
echo "   Creating symlink..."
sudo ln -s "$INSTALL_PREFIX/git-foil/bin/git-foil" "$INSTALL_PREFIX/bin/git-foil"

# Verify installation
echo ""
echo "✅ Installation complete!"
echo ""
git-foil --version
echo ""
echo "📍 Installed to: $INSTALL_PREFIX/git-foil"
echo "🔗 Symlinked at: $INSTALL_PREFIX/bin/git-foil"
