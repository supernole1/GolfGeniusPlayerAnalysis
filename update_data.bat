@echo off
REM ============================================
REM GolfGenius Player Analysis - Update Standings
REM Scrapes fresh data from GolfGenius
REM ============================================

cd /d "%~dp0"

echo Running scraper...
Rscript scraper\scrape_players.R
if errorlevel 1 (
    echo.
    echo Scraper failed. Try running with --headed for debugging:
    echo   Rscript scraper\scrape_players.R --headed
    pause
    exit /b 1
)

echo.
echo Done! Refresh the page in your browser to see updated standings.
pause
