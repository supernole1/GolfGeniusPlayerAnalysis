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
- **Rate limiting**: ~11 out of 110 players got "Retry later" responses when scraping too fast (2s delay between requests). These are filtered out automatically.

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
- "Update Standings" button (shows instructions to run scraper)
- Augusta green (#1a472a) + gold (#d4a843) color scheme

## File Structure
```
GolfGeniusPlayerAnalysis/
├── scraper/
│   ├── scrape_players.R       # Main scraper (R + chromote)
│   └── explore.R              # Debug/exploration script
├── docs/
│   ├── index.html             # Web app (open directly, no server)
│   ├── css/styles.css
│   ├── js/app.js
│   └── data/data.js           # Scraped data as JS const
├── update_data.bat            # One-click: run scraper
├── CLAUDE.md                  # This file
├── README.md
└── .gitignore
```

## Common Tasks
- **Update data**: `Rscript scraper/scrape_players.R` or double-click `update_data.bat`
- **View app**: Open `docs/index.html` in browser (no server needed)
- **Debug scraping**: Check `scraper/debug_*.txt` and `scraper/debug_*.png` files
