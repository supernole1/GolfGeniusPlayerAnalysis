#!/usr/bin/env Rscript
# Quick exploration script to discover nav links and player detail pages

library(chromote)
library(jsonlite)

get_script_dir <- function() {
  cmd_args <- commandArgs(trailingOnly = FALSE)
  file_arg <- grep("^--file=", cmd_args, value = TRUE)
  if (length(file_arg) > 0) return(dirname(normalizePath(sub("^--file=", "", file_arg[1]), winslash = "/")))
  scraper_dir <- file.path(getwd(), "scraper")
  if (dir.exists(scraper_dir)) return(normalizePath(scraper_dir, winslash = "/"))
  return(normalizePath(getwd(), winslash = "/"))
}
SCRIPT_DIR <- get_script_dir()

b <- ChromoteSession$new()

# Stealth: override user-agent and hide webdriver flag
b$Network$setUserAgentOverride(
  userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36"
)
b$Runtime$evaluate("Object.defineProperty(navigator, 'webdriver', {get: () => undefined})")
cat("Stealth settings applied\n")

tryCatch({
  # Step 1: Go to league page, dump all nav links
  cat("=== STEP 1: League page nav links ===\n")
  b$Page$navigate("https://www.golfgenius.com/ggid/RUMBLERS")
  Sys.sleep(8)
  cat("Page URL:", b$Runtime$evaluate("window.location.href")$result$value, "\n")

  nav_links <- b$Runtime$evaluate("
    (function() {
      var links = document.querySelectorAll('a');
      var result = [];
      for (var i = 0; i < links.length; i++) {
        var text = links[i].textContent.trim();
        var href = links[i].href || '';
        if (text.length > 0 && text.length < 100) {
          result.push(text + ' -> ' + href);
        }
      }
      return result.join('\\n');
    })()
  ")$result$value
  cat(nav_links, "\n\n")

  # Step 2: Click on the first player in the analytics table to see detail page
  cat("=== STEP 2: Navigate to Player Analytics iframe ===\n")
  # Click Player Statistics link
  b$Runtime$evaluate("
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
  ")
  Sys.sleep(8)

  # Get iframe src
  iframe_src <- b$Runtime$evaluate("
    (function() {
      var iframe = document.querySelector('iframe.page-iframe') || document.querySelector('iframe');
      return iframe ? iframe.src : 'none';
    })()
  ")$result$value
  cat("Iframe src:", iframe_src, "\n")

  if (iframe_src == "none" || is.null(iframe_src)) {
    cat("No iframe found! Taking screenshot of current page...\n")
    ss <- b$Page$captureScreenshot(format = "png")
    writeBin(jsonlite::base64_dec(ss$data), file.path(SCRIPT_DIR, "debug_no_iframe.png"))
    page_text <- b$Runtime$evaluate("document.body.innerText")$result$value
    writeLines(page_text, file.path(SCRIPT_DIR, "debug_no_iframe.txt"))
    cat(substr(page_text, 1, 2000), "\n")
    stop("No iframe found")
  }

  # Navigate into iframe
  b$Page$navigate(iframe_src)
  Sys.sleep(5)

  # Step 3: Find and click the first player link
  cat("\n=== STEP 3: Click first player to see detail ===\n")

  # Get all player links in the table
  player_links <- b$Runtime$evaluate("
    (function() {
      var links = document.querySelectorAll('table a, .player-name a, a');
      var result = [];
      for (var i = 0; i < links.length; i++) {
        var text = links[i].textContent.trim();
        var href = links[i].href || '';
        if (text.length > 1 && href.length > 0) {
          result.push(text + ' -> ' + href);
        }
      }
      return result.join('\\n');
    })()
  ")$result$value
  cat("Player links found:\n", player_links, "\n\n")

  # Click the first real player link (skip headers/navigation)
  click_result <- b$Runtime$evaluate("
    (function() {
      var links = document.querySelectorAll('table a');
      if (links.length > 0) {
        links[0].click();
        return 'clicked: ' + links[0].textContent.trim() + ' -> ' + links[0].href;
      }
      // Try any link that looks like a player name
      links = document.querySelectorAll('a');
      for (var i = 0; i < links.length; i++) {
        var href = links[i].href || '';
        if (href.match(/player_detail|player_stats.*player/)) {
          links[i].click();
          return 'clicked: ' + links[i].textContent.trim() + ' -> ' + href;
        }
      }
      return 'no player links found';
    })()
  ")$result$value
  cat("Click result:", click_result, "\n")
  Sys.sleep(5)

  # Step 4: Capture what the detail page looks like
  cat("\n=== STEP 4: Player detail page content ===\n")
  detail_text <- b$Runtime$evaluate("document.body.innerText")$result$value
  writeLines(detail_text, file.path(SCRIPT_DIR, "debug_player_detail.txt"))
  cat("First 2000 chars:\n")
  cat(substr(detail_text, 1, 2000), "\n")

  # Screenshot
  ss <- b$Page$captureScreenshot(format = "png")
  writeBin(jsonlite::base64_dec(ss$data), file.path(SCRIPT_DIR, "debug_player_detail.png"))
  cat("\nScreenshot saved to debug_player_detail.png\n")

  # Also get the current URL
  current_url <- b$Runtime$evaluate("window.location.href")$result$value
  cat("Current URL:", current_url, "\n")

}, finally = {
  tryCatch(b$close(), error = function(e) NULL)
})
