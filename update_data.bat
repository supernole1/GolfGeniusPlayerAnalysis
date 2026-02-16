@echo off
REM ============================================
REM GolfGenius Player Analysis - Update Standings
REM Scrapes data, commits, and pushes to GitHub
REM ============================================

cd /d "%~dp0"

echo Running scraper...
Rscript scraper\scrape_players.R
if errorlevel 1 (
    echo.
    echo Scraper failed.
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
