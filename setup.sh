#!/bin/bash
set -e

echo "🔧 Foundry — Setup"
echo ""

# ------------------------------------------------------------------
# 1. Check prerequisites
# ------------------------------------------------------------------
check_cmd() {
  if ! command -v "$1" &>/dev/null; then
    echo "❌ $1 is required but not installed."
    [ -n "$2" ] && echo "   Install: $2"
    exit 1
  else
    echo "✅ $1 found ($(command -v "$1"))"
  fi
}

echo "Checking prerequisites..."
check_cmd "node"    "https://nodejs.org"
check_cmd "npm"     "comes with Node.js"
check_cmd "rustc"   "https://rustup.rs"
check_cmd "cargo"   "https://rustup.rs"
check_cmd "cmake"   "brew install cmake"
echo ""

# ------------------------------------------------------------------
# 2. Environment file
# ------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"
ENV_EXAMPLE="$SCRIPT_DIR/.env.example"

if [ -f "$ENV_FILE" ]; then
  echo "✅ .env file already exists"
else
  if [ -f "$ENV_EXAMPLE" ]; then
    cp "$ENV_EXAMPLE" "$ENV_FILE"
    echo "📝 Created .env from .env.example"
    echo ""
    echo "⚠️  Please edit .env and fill in your credentials:"
    echo "   $ENV_FILE"
    echo ""
    read -p "Open .env in your editor now? [Y/n] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
      ${EDITOR:-open} "$ENV_FILE"
    fi
  else
    echo "❌ .env.example not found"
    exit 1
  fi
fi
echo ""

# ------------------------------------------------------------------
# 3. Install npm dependencies
# ------------------------------------------------------------------
echo "Installing npm dependencies..."
cd "$SCRIPT_DIR"
npm install
echo ""

# ------------------------------------------------------------------
# 4. Check Rust toolchain
# ------------------------------------------------------------------
echo "Checking Rust toolchain..."
if command -v rustup &>/dev/null; then
  rustup target list --installed | grep -q "$(rustc -vV | grep host | awk '{print $2}')" && echo "✅ Rust target OK"
fi
echo ""

# ------------------------------------------------------------------
# 5. Verify .env is loaded
# ------------------------------------------------------------------
echo "Verifying .env..."
if grep -q "your-project" "$ENV_FILE" 2>/dev/null || grep -q "your-anon-key" "$ENV_FILE" 2>/dev/null; then
  echo "⚠️  .env still has placeholder values — update before running the app."
else
  echo "✅ .env looks configured"
fi
echo ""

# ------------------------------------------------------------------
# Done
# ------------------------------------------------------------------
echo "🎉 Setup complete! Run the app with:"
echo ""
echo "   npm run tauri dev"
echo ""
