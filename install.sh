#!/bin/bash
# Strava MCP Installer for Mac
# Usage: ./install.sh

set -e

echo "🚴 Strava MCP Installer"
echo "========================"
echo ""

# Determine script directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# 1. Check Python
echo "📦 Checking Python..."
if ! command -v python3 &> /dev/null; then
    echo "❌ Python 3 not found."
    echo "   Install via: brew install python"
    exit 1
fi
PYTHON_VERSION=$(python3 --version 2>&1)
echo "   ✅ $PYTHON_VERSION"

# 2. Virtual environment
echo ""
echo "📦 Setting up virtual environment..."
if [ ! -d "$SCRIPT_DIR/.venv" ]; then
    python3 -m venv "$SCRIPT_DIR/.venv"
    echo "   ✅ Created"
else
    echo "   ✅ Already exists"
fi

# 3. Install packages
echo ""
echo "📦 Installing packages..."
"$SCRIPT_DIR/.venv/bin/pip" install -q -r "$SCRIPT_DIR/requirements.txt"
echo "   ✅ Installed"

# 4. .env file
echo ""
if [ ! -f "$SCRIPT_DIR/.env" ]; then
    cp "$SCRIPT_DIR/.env.example" "$SCRIPT_DIR/.env"
    echo "📋 .env created from .env.example"
else
    echo "📋 .env already exists"
fi

# 5. Strava authorization
echo ""
echo "🔑 Starting Strava authorization..."
echo "   Your browser will open. Log in with your Strava account."
echo "   Then copy the redirect URL and paste it here."
echo ""
cd "$SCRIPT_DIR"
"$SCRIPT_DIR/.venv/bin/python" strava_auth.py

# 6. Claude Desktop config
echo ""
echo "⚙️  Configuring Claude Desktop..."
PYTHON_PATH="$SCRIPT_DIR/.venv/bin/python"
SERVER_PATH="$SCRIPT_DIR/server.py"
CONFIG_DIR="$HOME/Library/Application Support/Claude"
CONFIG_FILE="$CONFIG_DIR/claude_desktop_config.json"

mkdir -p "$CONFIG_DIR"

if [ -f "$CONFIG_FILE" ]; then
    # Existing config: add strava with python (paths via argv)
    "$SCRIPT_DIR/.venv/bin/python" -c "
import json, sys
config_file, python_path, server_path = sys.argv[1], sys.argv[2], sys.argv[3]
with open(config_file, 'r') as f:
    config = json.load(f)
if 'mcpServers' not in config:
    config['mcpServers'] = {}
config['mcpServers']['strava'] = {
    'command': python_path,
    'args': [server_path]
}
with open(config_file, 'w') as f:
    json.dump(config, f, indent=2)
print('   ✅ Strava added to existing config')
" "$CONFIG_FILE" "$PYTHON_PATH" "$SERVER_PATH"
else
    # New config
    cat > "$CONFIG_FILE" << CONFIGEOF
{
  "mcpServers": {
    "strava": {
      "command": "$PYTHON_PATH",
      "args": ["$SERVER_PATH"]
    }
  }
}
CONFIGEOF
    echo "   ✅ New config created"
fi

# Done!
echo ""
echo "========================================="
echo "🎉 Installation complete!"
echo "========================================="
echo ""
echo "Restart Claude Desktop (⌘+Q and reopen)"
echo "and ask: 'Show my last 5 rides'"
echo ""
