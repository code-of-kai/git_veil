#!/bin/bash
set -e

# Development installation script for git-veil
# Uses symlinks so rebuilds don't require reinstallation

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_PREFIX="${INSTALL_PREFIX:-/usr/local}"
BUILD_DIR="$SCRIPT_DIR/_build/dev/rel/git_veil"

echo "🔨 Building git-veil (dev mode)..."
cd "$SCRIPT_DIR"
mix release --overwrite

echo ""
echo "🔗 Installing git-veil (development mode with symlinks)..."

# Remove old installation if it exists
if [ -L "$INSTALL_PREFIX/bin/git-veil" ]; then
    echo "   Removing old symlink..."
    sudo rm "$INSTALL_PREFIX/bin/git-veil"
fi

if [ -L "$INSTALL_PREFIX/git-veil" ]; then
    echo "   Removing old symlink..."
    sudo rm "$INSTALL_PREFIX/git-veil"
elif [ -d "$INSTALL_PREFIX/git-veil" ]; then
    echo "   Removing old installation directory..."
    sudo rm -rf "$INSTALL_PREFIX/git-veil"
fi

# Create symlinks (no copying needed!)
echo "   Symlinking build directory to $INSTALL_PREFIX/git-veil..."
sudo ln -s "$BUILD_DIR" "$INSTALL_PREFIX/git-veil"

echo "   Symlinking executable to $INSTALL_PREFIX/bin/git-veil..."
sudo ln -s "$BUILD_DIR/bin/git-veil" "$INSTALL_PREFIX/bin/git-veil"

# Verify installation
echo ""
echo "✅ Development installation complete!"
echo ""
git-veil --version
echo ""
echo "📍 Source:   $SCRIPT_DIR"
echo "🔗 Symlink:  $INSTALL_PREFIX/git-veil → $BUILD_DIR"
echo "🔗 Binary:   $INSTALL_PREFIX/bin/git-veil"
echo ""
echo "💡 Tip: Just run 'mix release --overwrite' to update. No need to reinstall!"
