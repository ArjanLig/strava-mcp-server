# Strava MCP Server

MCP (Model Context Protocol) server that connects your Strava training data to Claude Desktop. View activities, analyze training load (ATL/CTL/TSB), and get personalized training advice — all from Claude.

## Features

- **Recent activities** — view your latest rides with distance, duration, heart rate
- **Activity details** — deep dive into a specific activity (power, suffer score, etc.)
- **Weekly statistics** — volume, distance, and hours per week
- **Training load analysis** — ATL, CTL, TSB, ramp rate with injury risk warnings
- **Weekly training plan** — personalized plan based on your current fitness and fatigue

## Installation

### Option 1: DMG Installer (easiest)

1. Download the latest `.dmg` from [Releases](../../releases)
2. Open the DMG
3. Double-click **`Install Strava MCP.command`**
4. Follow the steps in Terminal
5. Restart Claude Desktop

### Option 2: Quick install from source

```bash
git clone https://github.com/ArjanLig/strava-mcp-server.git
cd strava-mcp-server
./install.sh
```

### Option 3: Manual installation

1. Clone the repo:
```bash
git clone https://github.com/ArjanLig/strava-mcp-server.git
cd strava-mcp-server
```

2. Create a virtual environment and install dependencies:
```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

3. Set up your Strava API credentials:
   - Go to https://www.strava.com/settings/api
   - Create a new application (Category: Data Analysis, Callback Domain: localhost)
   - Copy `.env.example` to `.env` and fill in your Client ID and Client Secret:
```bash
cp .env.example .env
```

4. Authorize with Strava:
```bash
python strava_auth.py
```

5. Add to Claude Desktop config (`~/Library/Application Support/Claude/claude_desktop_config.json`):
```json
{
  "mcpServers": {
    "strava": {
      "command": "/path/to/strava-mcp-server/.venv/bin/python",
      "args": ["/path/to/strava-mcp-server/server.py"]
    }
  }
}
```

6. Restart Claude Desktop.

## Usage

Ask Claude things like:
- "Show my last 5 rides"
- "Analyze my training load"
- "Should I rest or train today?"
- "Give me a weekly training plan"
- "Show details of my last activity"

## Building the DMG

To build the DMG installer yourself:

```bash
./build_dmg.sh
```

The DMG will be created in the `build/` folder.

## Requirements

- macOS
- Python 3.10+
- A Strava account with API access
- Claude Desktop

## License

MIT
