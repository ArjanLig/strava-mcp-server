#!/bin/bash
set -e

# Kleuren
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

clear
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}       Strava MCP Server — Installatie${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Bepaal waar het .command bestand staat (in de DMG of lokaal)
SOURCE_DIR="$(cd "$(dirname "$0")" && pwd)"

# Installatie locatie
INSTALL_DIR="$HOME/strava-mcp"

# ============= STAP 1: Python check =============
echo -e "${YELLOW}[1/6]${NC} Python controleren..."

if command -v python3 &> /dev/null; then
    PYTHON_CMD="python3"
    PYTHON_VERSION=$($PYTHON_CMD --version 2>&1)
    echo -e "  ${GREEN}✓${NC} $PYTHON_VERSION gevonden"
else
    echo -e "  ${YELLOW}!${NC} Python 3 niet gevonden. Wordt nu geinstalleerd..."
    echo ""

    # Detecteer chip type voor juiste installer
    ARCH=$(uname -m)
    if [ "$ARCH" = "arm64" ]; then
        PKG_URL="https://www.python.org/ftp/python/3.13.2/python-3.13.2-macos11.pkg"
    else
        PKG_URL="https://www.python.org/ftp/python/3.13.2/python-3.13.2-macos11.pkg"
    fi

    PKG_FILE="/tmp/python-installer.pkg"

    echo -e "  Downloaden van python.org..."
    curl -L -o "$PKG_FILE" "$PKG_URL" 2>/dev/null

    echo -e "  Installeren (je moet mogelijk je wachtwoord invoeren)..."
    sudo installer -pkg "$PKG_FILE" -target /
    rm -f "$PKG_FILE"

    # Refresh PATH zodat python3 gevonden wordt
    export PATH="/Library/Frameworks/Python.framework/Versions/3.13/bin:$PATH"

    if command -v python3 &> /dev/null; then
        PYTHON_CMD="python3"
        PYTHON_VERSION=$($PYTHON_CMD --version 2>&1)
        echo -e "  ${GREEN}✓${NC} $PYTHON_VERSION geinstalleerd"
    else
        echo -e "  ${RED}✗ Python installatie mislukt.${NC}"
        echo "  Download handmatig via https://www.python.org/downloads/"
        echo ""
        echo "  Druk op Enter om af te sluiten..."
        read
        exit 1
    fi
fi

# ============= STAP 2: Bestanden kopieren =============
echo -e "${YELLOW}[2/6]${NC} Bestanden installeren naar $INSTALL_DIR..."

if [ -d "$INSTALL_DIR" ]; then
    echo -e "  ${YELLOW}!${NC} Map $INSTALL_DIR bestaat al."
    read -p "  Overschrijven? (j/n): " OVERWRITE
    if [ "$OVERWRITE" != "j" ] && [ "$OVERWRITE" != "J" ]; then
        echo "  Installatie afgebroken."
        echo "  Druk op Enter om af te sluiten..."
        read
        exit 0
    fi
fi

mkdir -p "$INSTALL_DIR"
cp "$SOURCE_DIR/Server.py" "$INSTALL_DIR/"
cp "$SOURCE_DIR/strava_auth.py" "$INSTALL_DIR/"
cp "$SOURCE_DIR/requirements.txt" "$INSTALL_DIR/"

# Kopieer .env alleen als die nog niet bestaat (behoud bestaande tokens)
if [ ! -f "$INSTALL_DIR/.env" ]; then
    cp "$SOURCE_DIR/.env.example" "$INSTALL_DIR/.env"
fi

echo -e "  ${GREEN}✓${NC} Bestanden gekopieerd"

# ============= STAP 3: Virtual environment =============
echo -e "${YELLOW}[3/6]${NC} Virtual environment aanmaken..."

if [ -d "$INSTALL_DIR/.venv" ]; then
    echo -e "  ${GREEN}✓${NC} .venv bestaat al"
else
    $PYTHON_CMD -m venv "$INSTALL_DIR/.venv"
    echo -e "  ${GREEN}✓${NC} .venv aangemaakt"
fi

source "$INSTALL_DIR/.venv/bin/activate"

# ============= STAP 4: Dependencies =============
echo -e "${YELLOW}[4/6]${NC} Dependencies installeren..."

pip install --quiet --upgrade pip
pip install --quiet -r "$INSTALL_DIR/requirements.txt"
echo -e "  ${GREEN}✓${NC} Alle packages geinstalleerd"

# ============= STAP 5: Strava API credentials =============
echo -e "${YELLOW}[5/6]${NC} Strava API instellen..."
echo ""

# Check of credentials al bestaan
EXISTING_CLIENT_ID=""
if [ -f "$INSTALL_DIR/.env" ]; then
    EXISTING_CLIENT_ID=$(grep "^STRAVA_CLIENT_ID=" "$INSTALL_DIR/.env" | cut -d'=' -f2)
fi

if [ -n "$EXISTING_CLIENT_ID" ]; then
    echo -e "  ${GREEN}✓${NC} Strava credentials al geconfigureerd"
else
    echo -e "  ${BOLD}Je hebt een Strava API applicatie nodig.${NC}"
    echo ""
    echo "  Stap 1: Ga naar ${BLUE}https://www.strava.com/settings/api${NC}"
    echo "  Stap 2: Maak een nieuwe applicatie aan:"
    echo "          - Application Name: MCP Server"
    echo "          - Category: Data Analysis"
    echo "          - Website: http://localhost"
    echo "          - Authorization Callback Domain: localhost"
    echo ""

    read -p "  Strava Client ID: " CLIENT_ID
    read -p "  Strava Client Secret: " CLIENT_SECRET

    cat > "$INSTALL_DIR/.env" << EOF
STRAVA_CLIENT_ID=$CLIENT_ID
STRAVA_CLIENT_SECRET=$CLIENT_SECRET
STRAVA_ACCESS_TOKEN=
STRAVA_REFRESH_TOKEN=
EOF

    echo ""
    echo -e "  ${GREEN}✓${NC} Credentials opgeslagen"
    echo ""
    echo -e "  ${BOLD}Nu gaan we je Strava account koppelen...${NC}"
    echo ""

    cd "$INSTALL_DIR"
    $PYTHON_CMD "$INSTALL_DIR/strava_auth.py"
    echo ""
fi

# ============= STAP 6: Claude Desktop configuratie =============
echo -e "${YELLOW}[6/6]${NC} Claude Desktop configureren..."

VENV_PYTHON="$INSTALL_DIR/.venv/bin/python"
SERVER_PATH="$INSTALL_DIR/Server.py"

CLAUDE_CONFIG_DIR="$HOME/Library/Application Support/Claude"
CLAUDE_CONFIG_FILE="$CLAUDE_CONFIG_DIR/claude_desktop_config.json"

mkdir -p "$CLAUDE_CONFIG_DIR"

if [ -f "$CLAUDE_CONFIG_FILE" ]; then
    if grep -q '"strava"' "$CLAUDE_CONFIG_FILE"; then
        echo -e "  ${GREEN}✓${NC} Strava MCP al geconfigureerd in Claude Desktop"
    else
        # Voeg strava toe aan bestaande config met python (paden via argv)
        "$INSTALL_DIR/.venv/bin/python" -c "
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
" "$CLAUDE_CONFIG_FILE" "$VENV_PYTHON" "$SERVER_PATH"
        echo -e "  ${GREEN}✓${NC} Strava MCP toegevoegd aan bestaande Claude Desktop config"
    fi
else
    cat > "$CLAUDE_CONFIG_FILE" << EOF
{
  "mcpServers": {
    "strava": {
      "command": "$VENV_PYTHON",
      "args": [
        "$SERVER_PATH"
      ]
    }
  }
}
EOF
    echo -e "  ${GREEN}✓${NC} Claude Desktop config aangemaakt"
fi

# ============= KLAAR =============
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}       Installatie voltooid!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "  Herstart Claude Desktop om de Strava MCP te gebruiken."
echo ""
echo "  Beschikbare tools in Claude:"
echo "    - get_recent_activities       Recente ritten"
echo "    - get_activity_details        Details van een rit"
echo "    - get_weekly_stats            Wekelijkse stats"
echo "    - get_training_load_analysis  ATL/CTL/TSB analyse"
echo "    - get_weekly_training_plan    Weektraining advies"
echo ""
echo "  Geinstalleerd in: $INSTALL_DIR"
echo ""
echo "  Druk op Enter om af te sluiten..."
read
