#!/bin/bash
set -e

# Development installation script for git-foil
# Uses symlinks so rebuilds don't require reinstallation

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_PREFIX="${INSTALL_PREFIX:-/usr/local}"
BUILD_DIR="$SCRIPT_DIR/_build/dev/rel/git_foil"

echo "🔨 Building git-foil (dev mode)..."
cd "$SCRIPT_DIR"
mix release --overwrite

echo ""
echo "🔗 Installing git-foil (development mode with symlinks)..."

# Remove old installation if it exists
if [ -L "$INSTALL_PREFIX/bin/git-foil" ]; then
    echo "   Removing old symlink..."
    sudo rm "$INSTALL_PREFIX/bin/git-foil"
fi

if [ -L "$INSTALL_PREFIX/git-foil" ]; then
    echo "   Removing old symlink..."
    sudo rm "$INSTALL_PREFIX/git-foil"
elif [ -d "$INSTALL_PREFIX/git-foil" ]; then
    echo "   Removing old installation directory..."
    sudo rm -rf "$INSTALL_PREFIX/git-foil"
fi

# Create symlinks (no copying needed!)
echo "   Symlinking build directory to $INSTALL_PREFIX/git-foil..."
sudo ln -s "$BUILD_DIR" "$INSTALL_PREFIX/git-foil"

echo "   Symlinking executable to $INSTALL_PREFIX/bin/git-foil..."
sudo ln -s "$BUILD_DIR/bin/git-foil" "$INSTALL_PREFIX/bin/git-foil"

# Verify installation
echo ""
echo "✅ Development installation complete!"
echo ""
git-foil --version
echo ""
echo "📍 Source:   $SCRIPT_DIR"
echo "🔗 Symlink:  $INSTALL_PREFIX/git-foil → $BUILD_DIR"
echo "🔗 Binary:   $INSTALL_PREFIX/bin/git-foil"
echo ""
echo "💡 Tip: Just run 'mix release --overwrite' to update. No need to reinstall!"
