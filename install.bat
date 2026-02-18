@echo off
setlocal enabledelayedexpansion

echo ===================================================
echo        Strava MCP Server - Installation
echo ===================================================
echo.

set "INSTALL_DIR=%USERPROFILE%\strava-mcp"
set "SCRIPT_DIR=%~dp0"

:: ============= STEP 1: Python check =============
echo [1/6] Checking Python...

where python >nul 2>nul
if %errorlevel% equ 0 (
    for /f "tokens=*" %%i in ('python --version 2^>^&1') do set PYTHON_VERSION=%%i
    echo   OK: !PYTHON_VERSION! found
    set "PYTHON_CMD=python"
    goto :python_ok
)

where python3 >nul 2>nul
if %errorlevel% equ 0 (
    for /f "tokens=*" %%i in ('python3 --version 2^>^&1') do set PYTHON_VERSION=%%i
    echo   OK: !PYTHON_VERSION! found
    set "PYTHON_CMD=python3"
    goto :python_ok
)

echo   Python 3 not found.
echo.
echo   This installer will download Python 3.13 from python.org
echo   and install it automatically.
echo.
set /p INSTALL_PYTHON="  Continue? (y/n): "
if /i not "!INSTALL_PYTHON!"=="y" (
    echo   Installation cancelled. Install Python manually from https://www.python.org/downloads/
    pause
    exit /b 1
)
echo.

:: Download Python installer
echo   Downloading from python.org...
powershell -Command "Invoke-WebRequest -Uri 'https://www.python.org/ftp/python/3.13.2/python-3.13.2-amd64.exe' -OutFile '%TEMP%\python-installer.exe'"

:: Install Python (silent, with PATH)
echo   Installing...
"%TEMP%\python-installer.exe" /quiet InstallAllUsers=0 PrependPath=1 Include_test=0

:: Wait for installation to finish
timeout /t 5 /nobreak >nul

:: Refresh PATH
set "PATH=%LOCALAPPDATA%\Programs\Python\Python313;%LOCALAPPDATA%\Programs\Python\Python313\Scripts;%PATH%"

del "%TEMP%\python-installer.exe" 2>nul

where python >nul 2>nul
if %errorlevel% equ 0 (
    set "PYTHON_CMD=python"
    for /f "tokens=*" %%i in ('python --version 2^>^&1') do set PYTHON_VERSION=%%i
    echo   OK: !PYTHON_VERSION! installed
) else (
    echo   ERROR: Python installation failed.
    echo   Download manually from https://www.python.org/downloads/
    pause
    exit /b 1
)

:python_ok

:: ============= STEP 2: Copy files =============
echo.
echo [2/6] Installing files to %INSTALL_DIR%...

if exist "%INSTALL_DIR%" (
    set /p OVERWRITE="  Directory already exists. Overwrite? (y/n): "
    if /i not "!OVERWRITE!"=="y" (
        echo   Installation cancelled.
        pause
        exit /b 0
    )
)

mkdir "%INSTALL_DIR%" 2>nul
copy /y "%SCRIPT_DIR%server.py" "%INSTALL_DIR%\" >nul
copy /y "%SCRIPT_DIR%strava_auth.py" "%INSTALL_DIR%\" >nul
copy /y "%SCRIPT_DIR%requirements.txt" "%INSTALL_DIR%\" >nul

if not exist "%INSTALL_DIR%\.env" (
    copy /y "%SCRIPT_DIR%.env.example" "%INSTALL_DIR%\.env" >nul
)

echo   OK: Files copied

:: ============= STEP 3: Virtual environment =============
echo.
echo [3/6] Creating virtual environment...

if exist "%INSTALL_DIR%\.venv" (
    echo   OK: .venv already exists
) else (
    %PYTHON_CMD% -m venv "%INSTALL_DIR%\.venv"
    echo   OK: .venv created
)

:: ============= STEP 4: Dependencies =============
echo.
echo [4/6] Installing dependencies...

"%INSTALL_DIR%\.venv\Scripts\pip.exe" install --quiet --upgrade pip
"%INSTALL_DIR%\.venv\Scripts\pip.exe" install --quiet -r "%INSTALL_DIR%\requirements.txt"
echo   OK: All packages installed

:: ============= STEP 5: Strava API credentials =============
echo.
echo [5/6] Setting up Strava API...
echo.

:: Check if credentials already exist
set "HAS_CREDENTIALS="
for /f "tokens=2 delims==" %%a in ('findstr "^STRAVA_CLIENT_ID=" "%INSTALL_DIR%\.env" 2^>nul') do (
    if not "%%a"=="your_client_id_here" if not "%%a"=="" set "HAS_CREDENTIALS=1"
)

if defined HAS_CREDENTIALS (
    echo   OK: Strava credentials already configured
) else (
    echo   You need a Strava API application.
    echo.
    echo   Step 1: Go to https://www.strava.com/settings/api
    echo   Step 2: Create a new application:
    echo           - Application Name: MCP Server
    echo           - Category: Data Analysis
    echo           - Website: http://localhost
    echo           - Authorization Callback Domain: localhost
    echo.

    set /p CLIENT_ID="  Strava Client ID: "
    set /p CLIENT_SECRET="  Strava Client Secret: "

    (
        echo STRAVA_CLIENT_ID=!CLIENT_ID!
        echo STRAVA_CLIENT_SECRET=!CLIENT_SECRET!
        echo STRAVA_ACCESS_TOKEN=
        echo STRAVA_REFRESH_TOKEN=
    ) > "%INSTALL_DIR%\.env"

    echo.
    echo   OK: Credentials saved
    echo.
    echo   Now we'll connect your Strava account...
    echo.

    cd /d "%INSTALL_DIR%"
    "%INSTALL_DIR%\.venv\Scripts\python.exe" "%INSTALL_DIR%\strava_auth.py"
    echo.
)

:: ============= STEP 6: Configure Claude Desktop =============
echo.
echo [6/6] Configuring Claude Desktop...

set "VENV_PYTHON=%INSTALL_DIR%\.venv\Scripts\python.exe"
set "SERVER_PATH=%INSTALL_DIR%\server.py"
set "CLAUDE_CONFIG_DIR=%APPDATA%\Claude"
set "CLAUDE_CONFIG_FILE=%CLAUDE_CONFIG_DIR%\claude_desktop_config.json"

mkdir "%CLAUDE_CONFIG_DIR%" 2>nul

if exist "%CLAUDE_CONFIG_FILE%" (
    findstr /c:"\"strava\"" "%CLAUDE_CONFIG_FILE%" >nul 2>nul
    if !errorlevel! equ 0 (
        echo   OK: Strava MCP already configured in Claude Desktop
    ) else (
        "%INSTALL_DIR%\.venv\Scripts\python.exe" -c "import json,sys;f=open(sys.argv[1],'r');c=json.load(f);f.close();c.setdefault('mcpServers',{});c['mcpServers']['strava']={'command':sys.argv[2],'args':[sys.argv[3]]};f=open(sys.argv[1],'w');json.dump(c,f,indent=2);f.close()" "%CLAUDE_CONFIG_FILE%" "%VENV_PYTHON%" "%SERVER_PATH%"
        echo   OK: Strava MCP added to existing Claude Desktop config
    )
) else (
    "%INSTALL_DIR%\.venv\Scripts\python.exe" -c "import json,sys;c={'mcpServers':{'strava':{'command':sys.argv[1],'args':[sys.argv[2]]}}};f=open(sys.argv[3],'w');json.dump(c,f,indent=2);f.close()" "%VENV_PYTHON%" "%SERVER_PATH%" "%CLAUDE_CONFIG_FILE%"
    echo   OK: Claude Desktop config created
)

:: ============= DONE =============
echo.
echo ===================================================
echo        Installation complete!
echo ===================================================
echo.
echo   Restart Claude Desktop to use the Strava MCP.
echo.
echo   Available tools in Claude:
echo     - get_recent_activities       Recent rides
echo     - get_activity_details        Activity details
echo     - get_weekly_stats            Weekly stats
echo     - get_training_load_analysis  ATL/CTL/TSB analysis
echo     - get_weekly_training_plan    Weekly training advice
echo.
echo   Installed in: %INSTALL_DIR%
echo.
pause
