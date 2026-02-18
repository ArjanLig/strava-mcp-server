#!/bin/bash
# Strava MCP Installer voor Mac
# Gebruik: ./install.sh

set -e

echo "🚴 Strava MCP Installer"
echo "========================"
echo ""

# Bepaal script directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# 1. Check Python
echo "📦 Python controleren..."
if ! command -v python3 &> /dev/null; then
    echo "❌ Python 3 niet gevonden."
    echo "   Installeer via: brew install python"
    exit 1
fi
PYTHON_VERSION=$(python3 --version 2>&1)
echo "   ✅ $PYTHON_VERSION"

# 2. Virtual environment
echo ""
echo "📦 Virtual environment opzetten..."
if [ ! -d "$SCRIPT_DIR/.venv" ]; then
    python3 -m venv "$SCRIPT_DIR/.venv"
    echo "   ✅ Aangemaakt"
else
    echo "   ✅ Bestaat al"
fi

# 3. Packages installeren
echo ""
echo "📦 Packages installeren..."
"$SCRIPT_DIR/.venv/bin/pip" install -q -r "$SCRIPT_DIR/requirements.txt"
echo "   ✅ Geïnstalleerd"

# 4. .env bestand
echo ""
if [ ! -f "$SCRIPT_DIR/.env" ]; then
    cp "$SCRIPT_DIR/.env.example" "$SCRIPT_DIR/.env"
    echo "📋 .env aangemaakt vanuit .env.example"
else
    echo "📋 .env bestaat al"
fi

# 5. Strava autorisatie
echo ""
echo "🔑 Strava autorisatie starten..."
echo "   Je browser opent zo. Log in met je Strava account."
echo "   Kopieer daarna de redirect URL en plak deze hier."
echo ""
cd "$SCRIPT_DIR"
"$SCRIPT_DIR/.venv/bin/python" strava_auth.py

# 6. Claude Desktop config
echo ""
echo "⚙️  Claude Desktop configureren..."
PYTHON_PATH="$SCRIPT_DIR/.venv/bin/python"
SERVER_PATH="$SCRIPT_DIR/server.py"
CONFIG_DIR="$HOME/Library/Application Support/Claude"
CONFIG_FILE="$CONFIG_DIR/claude_desktop_config.json"

mkdir -p "$CONFIG_DIR"

if [ -f "$CONFIG_FILE" ]; then
    # Bestaande config: voeg strava toe met python
    "$SCRIPT_DIR/.venv/bin/python" -c "
import json
with open('$CONFIG_FILE', 'r') as f:
    config = json.load(f)
if 'mcpServers' not in config:
    config['mcpServers'] = {}
config['mcpServers']['strava'] = {
    'command': '$PYTHON_PATH',
    'args': ['$SERVER_PATH']
}
with open('$CONFIG_FILE', 'w') as f:
    json.dump(config, f, indent=2)
print('   ✅ Strava toegevoegd aan bestaande config')
"
else
    # Nieuwe config
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
    echo "   ✅ Nieuwe config aangemaakt"
fi

# Klaar!
echo ""
echo "========================================="
echo "🎉 Installatie voltooid!"
echo "========================================="
echo ""
echo "Herstart Claude Desktop (⌘+Q en opnieuw openen)"
echo "en vraag: 'Haal mijn laatste 5 ritten op'"
echo ""
