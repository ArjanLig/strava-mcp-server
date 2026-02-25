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

1. Go to [https://www.strava.com/settings/api](https://www.strava.com/settings/api) and create a new application (Category: **Data Analysis**, Callback Domain: **localhost**). Note your **Client ID** and **Client Secret**.
2. Download the latest `.dmg` from [Releases](../../releases)
3. Open the DMG
4. Double-click **`Install Strava MCP.command`**
5. Follow the steps in Terminal — you'll be asked for your Client ID and Secret
6. Restart Claude Desktop

### Option 2: Quick install from source (macOS/Linux)

```bash
git clone https://github.com/ArjanLig/strava-mcp-server.git
cd strava-mcp-server
./install.sh
```

### Option 3: Windows installer

```cmd
git clone https://github.com/ArjanLig/strava-mcp-server.git
cd strava-mcp-server
install.bat
```

The batch file handles everything: Python check (with auto-download), virtual environment, dependencies, Strava authorization, and Claude Desktop configuration.

### Option 4: Manual installation

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

5. Add to Claude Desktop config:

   **macOS:** `~/Library/Application Support/Claude/claude_desktop_config.json`
   **Windows:** `%APPDATA%\Claude\claude_desktop_config.json`

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

On Windows, use backslashes and the `Scripts` directory instead:
```json
{
  "mcpServers": {
    "strava": {
      "command": "C:\\Users\\YOU\\strava-mcp\\.venv\\Scripts\\python.exe",
      "args": ["C:\\Users\\YOU\\strava-mcp\\server.py"]
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

## Building the DMG (macOS only)

To build the macOS DMG installer yourself:

```bash
./build_dmg.sh
```

The DMG will be created in the `build/` folder. Windows users can use `install.bat` directly — no DMG needed.

## Requirements

- macOS or Windows 10+
- Python 3.10+
- A Strava account with API access
- Claude Desktop

## License

MIT

<!-- mcp-name: io.github.ArjanLig/strava-training-mcp -->
