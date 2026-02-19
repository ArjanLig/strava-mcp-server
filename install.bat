@echo off
setlocal enabledelayedexpansion

echo ===================================================
echo        Strava MCP Server - Installatie
echo ===================================================
echo.

set "INSTALL_DIR=%USERPROFILE%\strava-mcp"
set "SCRIPT_DIR=%~dp0"

:: ============= STAP 1: Python check =============
echo [1/6] Python controleren...

where python >nul 2>nul
if %errorlevel% equ 0 (
    for /f "tokens=*" %%i in ('python --version 2^>^&1') do set PYTHON_VERSION=%%i
    echo   OK: !PYTHON_VERSION! gevonden
    set "PYTHON_CMD=python"
    goto :python_ok
)

where python3 >nul 2>nul
if %errorlevel% equ 0 (
    for /f "tokens=*" %%i in ('python3 --version 2^>^&1') do set PYTHON_VERSION=%%i
    echo   OK: !PYTHON_VERSION! gevonden
    set "PYTHON_CMD=python3"
    goto :python_ok
)

echo   Python 3 niet gevonden. Wordt nu geinstalleerd...
echo.

:: Download Python installer
echo   Downloaden van python.org...
powershell -Command "Invoke-WebRequest -Uri 'https://www.python.org/ftp/python/3.13.2/python-3.13.2-amd64.exe' -OutFile '%TEMP%\python-installer.exe'"

:: Installeer Python (silent, met PATH)
echo   Installeren...
"%TEMP%\python-installer.exe" /quiet InstallAllUsers=0 PrependPath=1 Include_test=0

:: Wacht even tot installatie klaar is
timeout /t 5 /nobreak >nul

:: Refresh PATH
set "PATH=%LOCALAPPDATA%\Programs\Python\Python313;%LOCALAPPDATA%\Programs\Python\Python313\Scripts;%PATH%"

del "%TEMP%\python-installer.exe" 2>nul

where python >nul 2>nul
if %errorlevel% equ 0 (
    set "PYTHON_CMD=python"
    for /f "tokens=*" %%i in ('python --version 2^>^&1') do set PYTHON_VERSION=%%i
    echo   OK: !PYTHON_VERSION! geinstalleerd
) else (
    echo   FOUT: Python installatie mislukt.
    echo   Download handmatig via https://www.python.org/downloads/
    pause
    exit /b 1
)

:python_ok

:: ============= STAP 2: Bestanden kopieren =============
echo.
echo [2/6] Bestanden installeren naar %INSTALL_DIR%...

if exist "%INSTALL_DIR%" (
    set /p OVERWRITE="  Map bestaat al. Overschrijven? (j/n): "
    if /i not "!OVERWRITE!"=="j" (
        echo   Installatie afgebroken.
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

echo   OK: Bestanden gekopieerd

:: ============= STAP 3: Virtual environment =============
echo.
echo [3/6] Virtual environment aanmaken...

if exist "%INSTALL_DIR%\.venv" (
    echo   OK: .venv bestaat al
) else (
    %PYTHON_CMD% -m venv "%INSTALL_DIR%\.venv"
    echo   OK: .venv aangemaakt
)

:: ============= STAP 4: Dependencies =============
echo.
echo [4/6] Dependencies installeren...

"%INSTALL_DIR%\.venv\Scripts\pip.exe" install --quiet --upgrade pip
"%INSTALL_DIR%\.venv\Scripts\pip.exe" install --quiet -r "%INSTALL_DIR%\requirements.txt"
echo   OK: Alle packages geinstalleerd

:: ============= STAP 5: Strava API credentials =============
echo.
echo [5/6] Strava API instellen...
echo.

:: Check of credentials al bestaan
set "HAS_CREDENTIALS="
for /f "tokens=2 delims==" %%a in ('findstr "^STRAVA_CLIENT_ID=" "%INSTALL_DIR%\.env" 2^>nul') do (
    if not "%%a"=="your_client_id_here" if not "%%a"=="" set "HAS_CREDENTIALS=1"
)

if defined HAS_CREDENTIALS (
    echo   OK: Strava credentials al geconfigureerd
) else (
    echo   Je hebt een Strava API applicatie nodig.
    echo.
    echo   Stap 1: Ga naar https://www.strava.com/settings/api
    echo   Stap 2: Maak een nieuwe applicatie aan:
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
    echo   OK: Credentials opgeslagen
    echo.
    echo   Nu gaan we je Strava account koppelen...
    echo.

    cd /d "%INSTALL_DIR%"
    "%INSTALL_DIR%\.venv\Scripts\python.exe" "%INSTALL_DIR%\strava_auth.py"
    echo.
)

:: ============= STAP 6: Claude Desktop configuratie =============
echo.
echo [6/6] Claude Desktop configureren...

set "VENV_PYTHON=%INSTALL_DIR%\.venv\Scripts\python.exe"
set "SERVER_PATH=%INSTALL_DIR%\server.py"
set "CLAUDE_CONFIG_DIR=%APPDATA%\Claude"
set "CLAUDE_CONFIG_FILE=%CLAUDE_CONFIG_DIR%\claude_desktop_config.json"

mkdir "%CLAUDE_CONFIG_DIR%" 2>nul

if exist "%CLAUDE_CONFIG_FILE%" (
    findstr /c:"\"strava\"" "%CLAUDE_CONFIG_FILE%" >nul 2>nul
    if !errorlevel! equ 0 (
        echo   OK: Strava MCP al geconfigureerd in Claude Desktop
    ) else (
        "%INSTALL_DIR%\.venv\Scripts\python.exe" -c "import json,sys;f=open(sys.argv[1],'r');c=json.load(f);f.close();c.setdefault('mcpServers',{});c['mcpServers']['strava']={'command':sys.argv[2],'args':[sys.argv[3]]};f=open(sys.argv[1],'w');json.dump(c,f,indent=2);f.close()" "%CLAUDE_CONFIG_FILE%" "%VENV_PYTHON%" "%SERVER_PATH%"
        echo   OK: Strava MCP toegevoegd aan bestaande Claude Desktop config
    )
) else (
    "%INSTALL_DIR%\.venv\Scripts\python.exe" -c "import json,sys;c={'mcpServers':{'strava':{'command':sys.argv[1],'args':[sys.argv[2]]}}};f=open(sys.argv[3],'w');json.dump(c,f,indent=2);f.close()" "%VENV_PYTHON%" "%SERVER_PATH%" "%CLAUDE_CONFIG_FILE%"
    echo   OK: Claude Desktop config aangemaakt
)

:: ============= KLAAR =============
echo.
echo ===================================================
echo        Installatie voltooid!
echo ===================================================
echo.
echo   Herstart Claude Desktop om de Strava MCP te gebruiken.
echo.
echo   Beschikbare tools in Claude:
echo     - get_recent_activities       Recente ritten
echo     - get_activity_details        Details van een rit
echo     - get_weekly_stats            Wekelijkse stats
echo     - get_training_load_analysis  ATL/CTL/TSB analyse
echo     - get_weekly_training_plan    Weektraining advies
echo.
echo   Geinstalleerd in: %INSTALL_DIR%
echo.
pause
