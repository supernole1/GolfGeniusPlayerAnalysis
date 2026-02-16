# GolfGenius Player Analysis

A web app that displays player money statistics scraped from a GolfGenius league. Data is collected using R with chromote (headless Chrome) and displayed in a sortable, searchable table you can open directly from your file system.

## Quick Start

1. Open `docs/index.html` in your browser (just double-click it)
2. To update data: double-click `update_data.bat` then refresh the page

## Setup

### Prerequisites
- R 4.0+ with packages: `chromote`, `jsonlite`
- Google Chrome (used by chromote for headless scraping)

### Install R Packages (if needed)

```r
install.packages(c("chromote", "jsonlite"))
```

## Usage

### Update Standings
Double-click `update_data.bat` — it runs the R scraper and updates the data file. Then refresh the browser page.

Or run manually:
```bash
Rscript scraper/scrape_players.R
Rscript scraper/scrape_players.R --headed   # debug mode (visible browser)
Rscript scraper/scrape_players.R --ggid RUMBLERS
```

### View Standings
Open `docs/index.html` directly in your browser. No server needed.

## Project Structure

```
GolfGeniusPlayerAnalysis/
├── scraper/
│   └── scrape_players.R       # chromote-based R scraper
├── docs/
│   ├── index.html             # Main web app (open directly)
│   ├── css/styles.css         # Golf-themed styling
│   ├── js/app.js              # Sorting, search, rendering
│   └── data/data.js           # Scraped data (output of scraper)
├── update_data.bat            # One-click update (Windows)
├── .gitignore
└── README.md
```

## Columns

| Column | Description |
|--------|-------------|
| Player | Player name |
| Money Won | Total money won from GolfGenius |
| Rounds | Number of rounds played |
| Purse Entered | $15 x rounds played |
| Net | Money Won - Purse Entered |

## Notes

- First scraper run should use `--headed` to verify DOM selectors work with the live GolfGenius page
- If the scraper finds 0 players, run `--headed` to inspect and check debug files in `scraper/`
- The "Update Standings" button on the web page shows instructions for running the scraper
