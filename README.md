# 🚴 Strava MCP Server

MCP (Model Context Protocol) server die Strava trainingsdata beschikbaar maakt in Claude Desktop. Haal je activiteiten op, analyseer je training load (ATL/CTL/TSB), en krijg trainingsadvies direct vanuit Claude.

## Features

- **Recente activiteiten** ophalen
- **Activiteit details** bekijken (afstand, hartslag, power, suffer score)
- **Wekelijkse statistieken** (volume, afstand, uren)
- **Training Load analyse** (ATL, CTL, TSB, ramp rate)
- **Weektraining plan** op basis van je huidige status

## Installatie

### Snelle installatie (Mac)

```bash
./install.sh
```

### Handmatige installatie

1. Clone de repo:
```bash
git clone <repo-url>
cd strava-mcp
```

2. Maak virtual environment:
```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

3. Kopieer en vul `.env` in:
```bash
cp .env.example .env
```

4. Autoriseer met Strava:
```bash
python strava_auth.py
```

5. Voeg toe aan Claude Desktop config (`~/Library/Application Support/Claude/claude_desktop_config.json`):
```json
{
  "mcpServers": {
    "strava": {
      "command": "/pad/naar/strava-mcp/.venv/bin/python",
      "args": ["/pad/naar/strava-mcp/server.py"]
    }
  }
}
```

6. Herstart Claude Desktop.

## Gebruik

Vraag Claude bijvoorbeeld:
- "Haal mijn laatste 5 ritten op"
- "Analyseer mijn training load"
- "Moet ik vandaag rusten of trainen?"
- "Geef me een weekplan"

## Ontwikkeling

Gebruik Claude Code om features toe te voegen of te verbeteren:
```bash
cd ~/Documents/GitHub/strava-mcp
claude
```
