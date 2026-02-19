#!/bin/bash
set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
DMG_NAME="Strava-MCP-Installer"
BUILD_DIR="$PROJECT_DIR/build"
STAGING_DIR="$BUILD_DIR/dmg-staging"
DMG_PATH="$BUILD_DIR/$DMG_NAME.dmg"

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Strava MCP — DMG Builder${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Opruimen vorige build
rm -rf "$BUILD_DIR"
mkdir -p "$STAGING_DIR/Strava MCP"

echo -e "${YELLOW}[1/3]${NC} Bestanden kopieren..."

# Kopieer project bestanden
cp "$PROJECT_DIR/Server.py"         "$STAGING_DIR/Strava MCP/"
cp "$PROJECT_DIR/strava_auth.py"    "$STAGING_DIR/Strava MCP/"
cp "$PROJECT_DIR/requirements.txt"  "$STAGING_DIR/Strava MCP/"
cp "$PROJECT_DIR/.env.example"      "$STAGING_DIR/Strava MCP/"

# Kopieer installer (op top-level voor zichtbaarheid)
cp "$PROJECT_DIR/Install Strava MCP.command" "$STAGING_DIR/Strava MCP/"
chmod +x "$STAGING_DIR/Strava MCP/Install Strava MCP.command"

echo -e "  ${GREEN}✓${NC} Bestanden gekopieerd"

echo -e "${YELLOW}[2/3]${NC} DMG aanmaken..."

# Maak DMG
hdiutil create \
    -volname "Strava MCP" \
    -srcfolder "$STAGING_DIR/Strava MCP" \
    -ov \
    -format UDZO \
    "$DMG_PATH" \
    > /dev/null

echo -e "  ${GREEN}✓${NC} DMG aangemaakt"

echo -e "${YELLOW}[3/3]${NC} Opruimen..."
rm -rf "$STAGING_DIR"
echo -e "  ${GREEN}✓${NC} Klaar"

# Resultaat
DMG_SIZE=$(du -h "$DMG_PATH" | cut -f1)

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  DMG succesvol gebouwd!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "  Bestand: $DMG_PATH"
echo "  Grootte: $DMG_SIZE"
echo ""
echo "  De gebruiker opent de DMG en dubbelklikt op:"
echo "  'Install Strava MCP.command'"
echo ""
