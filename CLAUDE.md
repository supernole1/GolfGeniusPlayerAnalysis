# GolfGenius Player Analysis - Project Context

## What This Project Does
Scrapes player purse/money data from the GolfGenius RUMBLERS league and displays it in a sortable web app. No server needed — open `docs/index.html` directly from the filesystem.

## Tech Stack
- **Scraper**: R (4.5.2) using `chromote` (headless Chrome via CDP) + `jsonlite`
- **Web app**: Vanilla HTML/CSS/JS — data loaded via `<script>` tag (not fetch), so it works from `file://`
- **No Python** — Python is not installed on this machine. R is at `C:\Program Files\R\R-4.5.2`
- **Node.js** is available (v24.13.0) if needed for utility scripts

## Key GolfGenius Findings (Hard-Won Knowledge)
- **League URL**: `https://www.golfgenius.com/ggid/RUMBLERS`
- **League ID**: `11870950312887994633`
- **Player Stats page ID**: `11870953009456368126` (shows scoring analytics, NOT money)
- **Players page ID**: `11870953007912864252`
- **Content loads inside `iframe.page-iframe`** via JavaScript
- **The "Player Statistics" page shows scoring stats** (eagles, birdies, pars) — NOT purse/money data
- **Purse/money data is on each player's DETAIL page** — click a player name to see their individual page header with: Name, Low Net, Low Gross, Purse, Rounds Played, Handicap Index
- **Player detail URL pattern**: `.../widgets/player_stats/member_info?member_id={ID}&page_id=11870953009456368126&shared=false`
- **Headless Chrome gets 403 Forbidden** unless you set a realistic user-agent and override `navigator.webdriver`
- **Stealth settings required**:
  - `Network.setUserAgentOverride` with a real Chrome UA string
  - `Object.defineProperty(navigator, 'webdriver', {get: () => undefined})`
- **Rate limiting**: ~11-19 out of 110 players get "Retry later" responses on first pass. Scraper has retry logic (up to 3 attempts with 10s pauses + 5s/page delays) that recovers all of them.

## Scraping Flow
1. Navigate to `/ggid/RUMBLERS` → page redirects to `/pages/11870953005966707194`
2. Click "Player Statistics" nav link
3. Wait for `iframe.page-iframe`, grab its `src` URL
4. Navigate directly to iframe URL to access content
5. Extract all `<table a[href*="member_info"]>` links (player names + detail URLs)
6. Visit each player's detail page, extract Purse and Rounds Played from body text via regex
7. Purse Entered = $15 × Rounds Played (league entry fee per round)
8. Output as `docs/data/data.js` (JavaScript const, not JSON)

## Data Format
`docs/data/data.js` contains `const PLAYER_DATA = { ... };` with:
- `ggid`, `league_name`, `scraped_at`, `player_count`, `purse_per_round`
- `players[]` array: `name`, `money`, `money_display`, `rounds_played`, `purse_entered`, `purse_display`

## Web App Features
- 3 summary cards (Players / Total Money Won / Avg per Player)
- Sortable table: #, Player, Money Won, Rounds, Purse Entered, Net
- Net column: green if positive, red if negative
- Live search/filter by player name
- "Update Standings" button triggers GitHub Actions workflow via API (PAT stored in browser localStorage)
- Augusta green (#1a472a) + gold (#d4a843) color scheme

## GitHub Actions
- Workflow: `.github/workflows/update-standings.yml`
- Trigger: `workflow_dispatch` (manual via API or GitHub UI)
- The "Update Standings" button in the web app calls `POST /repos/supernole1/GolfGeniusPlayerAnalysis/actions/workflows/update-standings.yml/dispatches`
- Requires a GitHub PAT with `actions:write` permission — stored in the user's browser localStorage (key: `gh_pat`), never in the repo
- After triggering, the button polls the workflow status every 10s and auto-reloads when complete
- The workflow: installs R + chromote + Chrome on Ubuntu, runs the scraper, commits + pushes updated data.js
- GitHub Pages auto-redeploys after the push

## File Structure
```
GolfGeniusPlayerAnalysis/
├── .github/workflows/
│   └── update-standings.yml   # GitHub Actions: run scraper + commit
├── scraper/
│   ├── scrape_players.R       # Main scraper (R + chromote)
│   └── explore.R              # Debug/exploration script
├── docs/
│   ├── index.html             # Web app (open directly, no server)
│   ├── css/styles.css
│   ├── js/app.js
│   └── data/data.js           # Scraped data as JS const
├── update_data.bat            # One-click: run scraper locally
├── CLAUDE.md                  # This file
├── README.md
└── .gitignore
```

## Common Tasks
- **Update data (from web app)**: Click "Update Standings" button (needs GitHub PAT on first use)
- **Update data (local)**: `Rscript scraper/scrape_players.R` or double-click `update_data.bat`
- **View app**: Open `docs/index.html` or visit `https://supernole1.github.io/GolfGeniusPlayerAnalysis/`
- **Debug scraping**: Check `scraper/debug_*.txt` and `scraper/debug_*.png` files
- **GitHub CLI**: installed at `C:\Program Files\GitHub CLI\gh.exe` (not on MSYS PATH, use full path)
