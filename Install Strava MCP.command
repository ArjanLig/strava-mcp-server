#!/bin/bash
set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

clear
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}       Strava MCP Server — Installation${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Determine where the .command file is located
SOURCE_DIR="$(cd "$(dirname "$0")" && pwd)"

# Installation location
INSTALL_DIR="$HOME/strava-mcp"

# ============= STEP 1: Python check =============
echo -e "${YELLOW}[1/6]${NC} Checking Python..."

if command -v python3 &> /dev/null; then
    PYTHON_CMD="python3"
    PYTHON_VERSION=$($PYTHON_CMD --version 2>&1)
    echo -e "  ${GREEN}✓${NC} $PYTHON_VERSION found"
else
    echo -e "  ${YELLOW}!${NC} Python 3 not found. Installing now..."
    echo ""

    # Detect chip type for correct installer
    ARCH=$(uname -m)
    if [ "$ARCH" = "arm64" ]; then
        PKG_URL="https://www.python.org/ftp/python/3.13.2/python-3.13.2-macos11.pkg"
    else
        PKG_URL="https://www.python.org/ftp/python/3.13.2/python-3.13.2-macos11.pkg"
    fi

    PKG_FILE="/tmp/python-installer.pkg"

    echo -e "  Downloading from python.org..."
    curl -L -o "$PKG_FILE" "$PKG_URL" 2>/dev/null

    echo -e "  Installing (you may need to enter your password)..."
    sudo installer -pkg "$PKG_FILE" -target /
    rm -f "$PKG_FILE"

    # Refresh PATH so python3 can be found
    export PATH="/Library/Frameworks/Python.framework/Versions/3.13/bin:$PATH"

    if command -v python3 &> /dev/null; then
        PYTHON_CMD="python3"
        PYTHON_VERSION=$($PYTHON_CMD --version 2>&1)
        echo -e "  ${GREEN}✓${NC} $PYTHON_VERSION installed"
    else
        echo -e "  ${RED}✗ Python installation failed.${NC}"
        echo "  Download manually from https://www.python.org/downloads/"
        echo ""
        echo "  Press Enter to close..."
        read
        exit 1
    fi
fi

# ============= STEP 2: Copy files =============
echo -e "${YELLOW}[2/6]${NC} Installing files to $INSTALL_DIR..."

if [ -d "$INSTALL_DIR" ]; then
    echo -e "  ${YELLOW}!${NC} Directory $INSTALL_DIR already exists."
    read -p "  Overwrite? (y/n): " OVERWRITE
    if [ "$OVERWRITE" != "y" ] && [ "$OVERWRITE" != "Y" ]; then
        echo "  Installation cancelled."
        echo "  Press Enter to close..."
        read
        exit 0
    fi
fi

mkdir -p "$INSTALL_DIR"
cp "$SOURCE_DIR/server.py" "$INSTALL_DIR/"
cp "$SOURCE_DIR/strava_auth.py" "$INSTALL_DIR/"
cp "$SOURCE_DIR/requirements.txt" "$INSTALL_DIR/"

# Only copy .env if it doesn't exist yet (preserve existing tokens)
if [ ! -f "$INSTALL_DIR/.env" ]; then
    cp "$SOURCE_DIR/.env.example" "$INSTALL_DIR/.env"
fi

echo -e "  ${GREEN}✓${NC} Files copied"

# ============= STEP 3: Virtual environment =============
echo -e "${YELLOW}[3/6]${NC} Creating virtual environment..."

if [ -d "$INSTALL_DIR/.venv" ]; then
    echo -e "  ${GREEN}✓${NC} .venv already exists"
else
    $PYTHON_CMD -m venv "$INSTALL_DIR/.venv"
    echo -e "  ${GREEN}✓${NC} .venv created"
fi

source "$INSTALL_DIR/.venv/bin/activate"

# ============= STEP 4: Dependencies =============
echo -e "${YELLOW}[4/6]${NC} Installing dependencies..."

pip install --quiet --upgrade pip
pip install --quiet -r "$INSTALL_DIR/requirements.txt"
echo -e "  ${GREEN}✓${NC} All packages installed"

# ============= STEP 5: Strava API credentials =============
echo -e "${YELLOW}[5/6]${NC} Setting up Strava API..."
echo ""

# Check if credentials already exist
EXISTING_CLIENT_ID=""
if [ -f "$INSTALL_DIR/.env" ]; then
    EXISTING_CLIENT_ID=$(grep "^STRAVA_CLIENT_ID=" "$INSTALL_DIR/.env" | cut -d'=' -f2)
fi

if [ -n "$EXISTING_CLIENT_ID" ]; then
    echo -e "  ${GREEN}✓${NC} Strava credentials already configured"
else
    echo -e "  ${BOLD}You need a Strava API application.${NC}"
    echo ""
    echo "  Step 1: Go to ${BLUE}https://www.strava.com/settings/api${NC}"
    echo "  Step 2: Create a new application:"
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
    echo -e "  ${GREEN}✓${NC} Credentials saved"
    echo ""
    echo -e "  ${BOLD}Now we'll connect your Strava account...${NC}"
    echo ""

    cd "$INSTALL_DIR"
    $PYTHON_CMD "$INSTALL_DIR/strava_auth.py"
    echo ""
fi

# ============= STEP 6: Configure Claude Desktop =============
echo -e "${YELLOW}[6/6]${NC} Configuring Claude Desktop..."

VENV_PYTHON="$INSTALL_DIR/.venv/bin/python"
SERVER_PATH="$INSTALL_DIR/server.py"

CLAUDE_CONFIG_DIR="$HOME/Library/Application Support/Claude"
CLAUDE_CONFIG_FILE="$CLAUDE_CONFIG_DIR/claude_desktop_config.json"

mkdir -p "$CLAUDE_CONFIG_DIR"

if [ -f "$CLAUDE_CONFIG_FILE" ]; then
    if grep -q '"strava"' "$CLAUDE_CONFIG_FILE"; then
        echo -e "  ${GREEN}✓${NC} Strava MCP already configured in Claude Desktop"
    else
        # Add strava to existing config with python (paths via argv)
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
        echo -e "  ${GREEN}✓${NC} Strava MCP added to existing Claude Desktop config"
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
    echo -e "  ${GREEN}✓${NC} Claude Desktop config created"
fi

# ============= DONE =============
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}       Installation complete!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "  Restart Claude Desktop to use the Strava MCP."
echo ""
echo "  Available tools in Claude:"
echo "    - get_recent_activities       Recent rides"
echo "    - get_activity_details        Activity details"
echo "    - get_weekly_stats            Weekly stats"
echo "    - get_training_load_analysis  ATL/CTL/TSB analysis"
echo "    - get_weekly_training_plan    Weekly training advice"
echo ""
echo "  Installed in: $INSTALL_DIR"
echo ""
echo "  Press Enter to close..."
read
