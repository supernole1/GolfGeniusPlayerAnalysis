@echo off
REM ============================================
REM GolfGenius Player Analysis - Update Standings
REM Scrapes data, commits, and pushes to GitHub
REM ============================================

cd /d "%~dp0"

REM Ensure Rscript is on PATH (may not be set when double-clicking)
where Rscript >nul 2>&1
if errorlevel 1 (
    if exist "C:\Program Files\R\R-4.5.2\bin\Rscript.exe" (
        set "PATH=C:\Program Files\R\R-4.5.2\bin;%PATH%"
    ) else (
        for /d %%D in ("C:\Program Files\R\R-*") do set "PATH=%%D\bin;%PATH%"
    )
)

REM Verify Rscript is available
where Rscript >nul 2>&1
if errorlevel 1 (
    echo ERROR: Rscript not found. Install R or add it to your PATH.
    pause
    exit /b 1
)

echo Running scraper...
echo (This takes ~5 minutes to scrape all players)
echo.

REM Run scraper, show output live AND save to log file
Rscript scraper\scrape_players.R > scraper_log.txt 2>&1
set SCRAPER_EXIT=%errorlevel%

REM Show the log output
type scraper_log.txt

if %SCRAPER_EXIT% neq 0 (
    echo.
    echo Scraper failed with exit code %SCRAPER_EXIT%.
    echo Full log saved to scraper_log.txt
    pause
    exit /b 1
)

echo.
echo Pushing to GitHub...
"C:\Program Files\GitHub CLI\gh.exe" auth status >nul 2>&1
if errorlevel 1 (
    echo Not logged into GitHub CLI. Run: gh auth login
    pause
    exit /b 1
)

git add docs\data\data.js
git commit -m "Update standings data - %date%"
git push

echo.
echo Done! Site will update in about a minute at:
echo https://supernole1.github.io/GolfGeniusPlayerAnalysis/
pause
