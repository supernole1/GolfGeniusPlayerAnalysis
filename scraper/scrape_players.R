#!/usr/bin/env Rscript
#
# GolfGenius Player Money Scraper
#
# Scrapes player purse and rounds data from a GolfGenius league.
# 1. Navigates to the Player Analytics page to get list of player URLs
# 2. Visits each player's detail page to extract Purse and Rounds Played
#
# Usage:
#   Rscript scrape_players.R
#   Rscript scrape_players.R --ggid RUMBLERS
#

library(chromote)
library(jsonlite)

# --- Configuration ---
args <- commandArgs(trailingOnly = TRUE)
GGID <- "RUMBLERS"
PURSE_PER_ROUND <- 15

for (i in seq_along(args)) {
  if (args[i] == "--ggid" && i < length(args)) GGID <- args[i + 1]
}

BASE_URL <- "https://www.golfgenius.com"
LEAGUE_URL <- paste0(BASE_URL, "/ggid/", GGID)

# Determine script directory
get_script_dir <- function() {
  cmd_args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", cmd_args, value = TRUE)
  if (length(file_arg) > 0) {
    return(dirname(normalizePath(sub("^--file=", "", file_arg[1]), winslash = "/")))
  }
  scraper_dir <- file.path(getwd(), "scraper")
  if (dir.exists(scraper_dir)) return(normalizePath(scraper_dir, winslash = "/"))
  return(normalizePath(getwd(), winslash = "/"))
}

SCRIPT_DIR <- get_script_dir()
OUTPUT_PATH <- file.path(dirname(SCRIPT_DIR), "docs", "data", "data.js")

cat("GolfGenius Player Money Scraper\n")
cat("================================\n")
cat("GGID:", GGID, "\n")
cat("Output:", OUTPUT_PATH, "\n\n")

# --- Launch headless Chrome ---
cat("Launching headless Chrome...\n")
b <- ChromoteSession$new()

# Stealth: override user-agent and hide webdriver flag
b$Network$setUserAgentOverride(
  userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36"
)
b$Runtime$evaluate("Object.defineProperty(navigator, 'webdriver', {get: () => undefined})")

tryCatch({
  # Step 1: Navigate to league page
  cat("Navigating to", LEAGUE_URL, "...\n")
  b$Page$navigate(LEAGUE_URL)
  Sys.sleep(8)

  # Step 2: Click Player Statistics link
  cat("Clicking Player Statistics...\n")
  click_result <- b$Runtime$evaluate("
    (function() {
      var links = document.querySelectorAll('a');
      for (var i = 0; i < links.length; i++) {
        if (links[i].textContent.trim().match(/player\\s*stat/i)) {
          links[i].click();
          return 'clicked';
        }
      }
      return 'not found';
    })()
  ")$result$value
  cat("  Result:", click_result, "\n")
  Sys.sleep(5)

  # Step 3: Get iframe URL and navigate into it
  cat("Finding iframe...\n")
  iframe_src <- b$Runtime$evaluate("
    (function() {
      var iframe = document.querySelector('iframe.page-iframe') || document.querySelector('iframe');
      return iframe ? iframe.src : 'none';
    })()
  ")$result$value

  if (iframe_src == "none" || is.null(iframe_src)) stop("Could not find iframe")
  cat("  Iframe:", iframe_src, "\n")

  b$Page$navigate(iframe_src)
  Sys.sleep(5)

  # Step 4: Extract all player detail URLs
  cat("Extracting player links...\n")
  player_json <- b$Runtime$evaluate("
    (function() {
      var links = document.querySelectorAll('table a[href*=\"member_info\"]');
      var players = [];
      for (var i = 0; i < links.length; i++) {
        players.push({name: links[i].textContent.trim(), url: links[i].href});
      }
      return JSON.stringify(players);
    })()
  ")$result$value

  player_urls <- fromJSON(player_json)
  cat("  Found", nrow(player_urls), "players\n\n")

  if (nrow(player_urls) == 0) stop("No player links found")

  # Step 5: Visit each player's detail page and extract purse + rounds
  # Helper function to scrape one player detail page
  scrape_player <- function(purl, wait = 2) {
    b$Page$navigate(purl)
    Sys.sleep(wait)

    detail <- b$Runtime$evaluate("
      (function() {
        var text = document.body.innerText;
        var purse = '';
        var rounds = '';
        var name = '';

        // Detect rate limiting / error pages
        if (text.match(/retry|error|forbidden|not found/i) && !text.match(/Purse:/)) {
          return JSON.stringify({error: true, raw: text.substring(0, 200)});
        }

        // Extract purse amount
        var purseMatch = text.match(/Purse:\\s*\\$([\\d,]+\\.?\\d*)/);
        if (purseMatch) purse = purseMatch[1];

        // Extract rounds played
        var roundsMatch = text.match(/Rounds\\s*Played:\\s*(\\d+)/);
        if (roundsMatch) rounds = roundsMatch[1];

        // Extract full name from header
        var lines = text.split('\\n');
        for (var j = 0; j < lines.length; j++) {
          var line = lines[j].trim();
          if (line.length > 2 && !line.match(/^(Back|Print|Low|Purse|Round|Handicap|Detail|Summary|Comparison|Hole|Gross)/)) {
            name = line;
            break;
          }
        }

        return JSON.stringify({error: false, name: name, purse: purse, rounds: rounds});
      })()
    ")$result$value

    fromJSON(detail)
  }

  players <- data.frame(
    name = character(0),
    money = numeric(0),
    rounds_played = integer(0),
    stringsAsFactors = FALSE
  )
  failed <- list()  # Track failed players for retry

  total <- nrow(player_urls)
  for (i in seq_len(total)) {
    pname <- player_urls$name[i]
    purl <- player_urls$url[i]

    cat(sprintf("  [%d/%d] %s ... ", i, total, pname))

    tryCatch({
      info <- scrape_player(purl, wait = 2)

      if (isTRUE(info$error)) {
        cat("RATE LIMITED - queued for retry\n")
        failed[[length(failed) + 1]] <- list(name = pname, url = purl)
        next
      }

      money <- as.numeric(gsub("[^0-9.]", "", info$purse))
      rounds <- as.integer(info$rounds)
      full_name <- if (nchar(info$name) > 0) info$name else pname
      if (is.na(money)) money <- 0
      if (is.na(rounds)) rounds <- 0L

      players <- rbind(players, data.frame(
        name = full_name, money = money, rounds_played = rounds,
        stringsAsFactors = FALSE
      ))
      cat(sprintf("$%.2f (%d rounds)\n", money, rounds))

    }, error = function(e) {
      cat("ERROR - queued for retry\n")
      failed[[length(failed) + 1]] <<- list(name = pname, url = purl)
    })
  }

  # Retry failed players with longer delays (up to 3 attempts)
  if (length(failed) > 0) {
    cat(sprintf("\n--- Retrying %d failed players (longer delays) ---\n", length(failed)))

    for (attempt in 1:3) {
      if (length(failed) == 0) break
      cat(sprintf("\n  Retry attempt %d (%d remaining)...\n", attempt, length(failed)))
      Sys.sleep(10)  # Pause before retry batch

      still_failed <- list()
      for (f in failed) {
        cat(sprintf("  [retry] %s ... ", f$name))

        tryCatch({
          info <- scrape_player(f$url, wait = 5)

          if (isTRUE(info$error)) {
            cat("still failing\n")
            still_failed[[length(still_failed) + 1]] <- f
            next
          }

          money <- as.numeric(gsub("[^0-9.]", "", info$purse))
          rounds <- as.integer(info$rounds)
          full_name <- if (nchar(info$name) > 0) info$name else f$name
          if (is.na(money)) money <- 0
          if (is.na(rounds)) rounds <- 0L

          players <- rbind(players, data.frame(
            name = full_name, money = money, rounds_played = rounds,
            stringsAsFactors = FALSE
          ))
          cat(sprintf("$%.2f (%d rounds)\n", money, rounds))

        }, error = function(e) {
          cat("ERROR\n")
          still_failed[[length(still_failed) + 1]] <<- f
        })
      }
      failed <- still_failed
    }

    # Report any players that still failed after all retries
    if (length(failed) > 0) {
      cat(sprintf("\nWARNING: %d players failed after all retries:\n", length(failed)))
      for (f in failed) cat("  -", f$name, "\n")
    }
  }

  # Add purse entered column
  players$purse_entered <- players$rounds_played * PURSE_PER_ROUND

  # Sort by money descending
  players <- players[order(-players$money), ]

  cat("\n================================\n")
  cat("Found", nrow(players), "players\n\n")
  for (i in seq_len(nrow(players))) {
    cat(sprintf("  %-20s  Purse: $%8.2f  Rounds: %3d  Entered: $%6.2f  Net: $%8.2f\n",
                players$name[i], players$money[i],
                players$rounds_played[i], players$purse_entered[i],
                players$money[i] - players$purse_entered[i]))
  }

  # Build output
  player_list <- lapply(seq_len(nrow(players)), function(i) {
    list(
      name = players$name[i],
      money = players$money[i],
      money_display = sprintf("$%.2f", players$money[i]),
      rounds_played = players$rounds_played[i],
      purse_entered = players$purse_entered[i],
      purse_display = sprintf("$%.2f", players$purse_entered[i])
    )
  })

  data <- list(
    ggid = GGID,
    league_name = "RBCC Rumblers",
    scraped_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    player_count = nrow(players),
    purse_per_round = PURSE_PER_ROUND,
    players = player_list
  )

  # Write as JavaScript file (works with file:// - no server needed)
  json_str <- toJSON(data, auto_unbox = TRUE, pretty = TRUE)
  js_content <- paste0("const PLAYER_DATA = ", json_str, ";\n")

  dir.create(dirname(OUTPUT_PATH), recursive = TRUE, showWarnings = FALSE)
  writeLines(js_content, OUTPUT_PATH, useBytes = FALSE)
  cat("\nData saved to", OUTPUT_PATH, "\n")

}, finally = {
  tryCatch(b$close(), error = function(e) NULL)
})
