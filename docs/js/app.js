(function () {
    'use strict';

    let allPlayers = [];
    let sortCol = 'money';
    let sortDir = 'desc';

    const $ = (sel) => document.querySelector(sel);
    const $$ = (sel) => document.querySelectorAll(sel);

    function escapeHtml(str) {
        const div = document.createElement('div');
        div.textContent = str;
        return div.innerHTML;
    }

    function formatMoney(n) {
        const sign = n < 0 ? '-' : '';
        return sign + '$' + Math.abs(n).toLocaleString('en-US', {
            minimumFractionDigits: 2,
            maximumFractionDigits: 2
        });
    }

    function updateSummary(players) {
        $('#player-count').textContent = players.length;
        const total = players.reduce((sum, p) => sum + p.money, 0);
        $('#total-purse').textContent = formatMoney(total);
        $('#avg-per-player').textContent = players.length
            ? formatMoney(total / players.length)
            : '--';
    }

    function sortPlayers(players) {
        const sorted = [...players];
        sorted.sort((a, b) => {
            let va = a[sortCol];
            let vb = b[sortCol];
            if (sortCol === 'rank') return 0; // rank is just row number
            if (typeof va === 'string') {
                va = va.toLowerCase();
                vb = vb.toLowerCase();
            }
            if (va < vb) return sortDir === 'asc' ? -1 : 1;
            if (va > vb) return sortDir === 'asc' ? 1 : -1;
            return 0;
        });
        return sorted;
    }

    function renderTable(players) {
        const tbody = $('#player-tbody');
        const sorted = sortPlayers(players);

        if (sorted.length === 0) {
            tbody.innerHTML = '';
            $('#player-table').style.display = 'none';
            $('#empty').style.display = 'block';
            return;
        }

        $('#empty').style.display = 'none';
        $('#player-table').style.display = 'table';

        tbody.innerHTML = sorted.map((p, i) => {
            const net = p.money - p.purse_entered;
            const netClass = net >= 0 ? 'net-positive' : 'net-negative';
            return `<tr>
                <td>${i + 1}</td>
                <td>${escapeHtml(p.name)}</td>
                <td>${escapeHtml(p.money_display || formatMoney(p.money))}</td>
                <td>${p.rounds_played}</td>
                <td>${escapeHtml(p.purse_display || formatMoney(p.purse_entered))}</td>
                <td class="${netClass}">${formatMoney(net)}</td>
            </tr>`;
        }).join('');

        // Update sort arrows
        $$('th.sortable').forEach(th => {
            th.classList.remove('sort-asc', 'sort-desc');
            if (th.dataset.sort === sortCol) {
                th.classList.add(sortDir === 'asc' ? 'sort-asc' : 'sort-desc');
            }
        });
    }

    function filterAndRender() {
        const query = $('#search-input').value.toLowerCase().trim();
        const filtered = query
            ? allPlayers.filter(p => p.name.toLowerCase().includes(query))
            : allPlayers;
        renderTable(filtered);
    }

    function setupSort() {
        $$('th.sortable').forEach(th => {
            th.addEventListener('click', () => {
                const col = th.dataset.sort;
                if (col === sortCol) {
                    sortDir = sortDir === 'asc' ? 'desc' : 'asc';
                } else {
                    sortCol = col;
                    sortDir = col === 'name' ? 'asc' : 'desc';
                }
                filterAndRender();
            });
        });
    }

    function setupSearch() {
        $('#search-input').addEventListener('input', filterAndRender);
    }

    const GITHUB_OWNER = 'supernole1';
    const GITHUB_REPO = 'GolfGeniusPlayerAnalysis';
    const WORKFLOW_FILE = 'update-standings.yml';

    function getToken() {
        return localStorage.getItem('gh_pat') || null;
    }

    function setupUpdateButton() {
        const btn = $('#update-btn');

        btn.addEventListener('click', async () => {
            let token = getToken();

            if (!token) {
                token = prompt(
                    'First-time setup: enter a GitHub Personal Access Token\n' +
                    'with "Actions (write)" permission.\n\n' +
                    'Create one at: github.com/settings/tokens\n\n' +
                    'This is saved in your browser only — never sent anywhere else.'
                );
                if (!token || !token.trim()) return;
                token = token.trim();
                localStorage.setItem('gh_pat', token);
            }

            btn.disabled = true;
            btn.textContent = 'Triggering...';

            try {
                const resp = await fetch(
                    `https://api.github.com/repos/${GITHUB_OWNER}/${GITHUB_REPO}/actions/workflows/${WORKFLOW_FILE}/dispatches`,
                    {
                        method: 'POST',
                        headers: {
                            'Authorization': `Bearer ${token}`,
                            'Accept': 'application/vnd.github.v3+json'
                        },
                        body: JSON.stringify({ ref: 'master' })
                    }
                );

                if (resp.status === 204) {
                    btn.textContent = 'Scraping...';
                    pollWorkflow(token, btn);
                } else if (resp.status === 401 || resp.status === 403) {
                    localStorage.removeItem('gh_pat');
                    alert('Token is invalid or expired. Click the button again to enter a new one.');
                    btn.disabled = false;
                    btn.textContent = 'Update Standings';
                } else {
                    const body = await resp.text();
                    alert('Failed to trigger update: ' + resp.status + '\n' + body);
                    btn.disabled = false;
                    btn.textContent = 'Update Standings';
                }
            } catch (err) {
                alert('Network error: ' + err.message);
                btn.disabled = false;
                btn.textContent = 'Update Standings';
            }
        });
    }

    // Workflow step names from update-standings.yml and estimated durations (seconds)
    const WORKFLOW_STEPS = [
        { name: 'Checkout repo', label: 'Starting up', duration: 5 },
        { name: 'Setup R', label: 'Installing R', duration: 90 },
        { name: 'Install system dependencies (Chrome)', label: 'Installing Chrome', duration: 30 },
        { name: 'Install R packages', label: 'Installing packages', duration: 60 },
        { name: 'Run scraper', label: 'Scraping players', duration: 300 },
        { name: 'Commit and push updated data', label: 'Saving data', duration: 10 }
    ];
    const TOTAL_PLAYERS = 110;
    const SCRAPE_STEP_NAME = 'Run scraper';
    // Estimated seconds from scraper start until player scraping begins (nav + iframe)
    const SCRAPE_OVERHEAD = 30;
    // Estimated seconds per player (including retries amortized)
    const SECS_PER_PLAYER = 2.5;

    async function pollWorkflow(token, btn) {
        const runsUrl = `https://api.github.com/repos/${GITHUB_OWNER}/${GITHUB_REPO}/actions/runs?per_page=1&event=workflow_dispatch`;
        const headers = {
            'Authorization': `Bearer ${token}`,
            'Accept': 'application/vnd.github.v3+json'
        };

        let attempts = 0;
        const maxAttempts = 90; // 15 minutes max
        const startTime = Date.now();

        const poll = setInterval(async () => {
            attempts++;
            const elapsed = Math.floor((Date.now() - startTime) / 1000);
            const elapsedMin = Math.floor(elapsed / 60);
            const elapsedSec = elapsed % 60;
            const timeStr = elapsedMin + ':' + String(elapsedSec).padStart(2, '0');

            try {
                const resp = await fetch(runsUrl, { headers });
                const data = await resp.json();
                const run = data.workflow_runs && data.workflow_runs[0];

                if (!run) {
                    btn.textContent = 'Waiting to start... (' + timeStr + ')';
                    return;
                }

                if (run.status === 'completed') {
                    clearInterval(poll);
                    if (run.conclusion === 'success') {
                        btn.textContent = 'Done! Reloading...';
                        setTimeout(() => window.location.reload(), 3000);
                    } else {
                        btn.textContent = 'Update Standings';
                        btn.disabled = false;
                        alert('Scraper finished with status: ' + run.conclusion + '\nCheck the Actions tab on GitHub for details.');
                    }
                    return;
                }

                // Get job steps for progress detail
                let stepLabel = 'Working';
                let playerProgress = '';

                try {
                    const jobsResp = await fetch(run.jobs_url, { headers });
                    const jobsData = await jobsResp.json();
                    const job = jobsData.jobs && jobsData.jobs[0];

                    if (job && job.steps) {
                        // Find the currently running step
                        const activeStep = job.steps.find(s => s.status === 'in_progress');
                        const completedSteps = job.steps.filter(s => s.status === 'completed');

                        if (activeStep) {
                            const matched = WORKFLOW_STEPS.find(ws => ws.name === activeStep.name);
                            stepLabel = matched ? matched.label : activeStep.name;

                            // Estimate player progress during scrape step
                            if (activeStep.name === SCRAPE_STEP_NAME && activeStep.started_at) {
                                const stepElapsed = (Date.now() - new Date(activeStep.started_at).getTime()) / 1000;
                                const scrapeTime = Math.max(0, stepElapsed - SCRAPE_OVERHEAD);
                                const estPlayers = Math.min(TOTAL_PLAYERS, Math.floor(scrapeTime / SECS_PER_PLAYER));
                                playerProgress = ' (' + estPlayers + '/' + TOTAL_PLAYERS + ' players)';
                            }
                        } else if (completedSteps.length > 0) {
                            stepLabel = 'Finishing up';
                        }
                    }
                } catch (e) { /* jobs API may not be ready yet */ }

                btn.textContent = stepLabel + playerProgress + ' - ' + timeStr;

            } catch (e) {
                btn.textContent = 'Updating... (' + timeStr + ')';
            }

            if (attempts >= maxAttempts) {
                clearInterval(poll);
                btn.textContent = 'Update Standings';
                btn.disabled = false;
                alert('Timed out waiting for scraper. Check the Actions tab on GitHub.');
            }
        }, 8000); // poll every 8 seconds
    }

    function loadData() {
        if (typeof PLAYER_DATA === 'undefined') {
            $('#error').style.display = 'block';
            $('#error').textContent = 'No data loaded. Run the scraper first (Rscript scraper/scrape_players.R)';
            return;
        }

        const data = PLAYER_DATA;

        allPlayers = (data.players || []).map(p => ({
            name: String(p.name || ''),
            money: Number(p.money) || 0,
            money_display: p.money_display || null,
            rounds_played: Number(p.rounds_played) || 0,
            purse_entered: Number(p.purse_entered) || 0,
            purse_display: p.purse_display || null,
            net: (Number(p.money) || 0) - (Number(p.purse_entered) || 0)
        }));

        if (data.ggid) {
            $('#ggid-input').value = data.ggid;
        }

        if (data.scraped_at) {
            const d = new Date(data.scraped_at);
            $('#data-info').textContent = 'Last updated: ' + d.toLocaleDateString() + ' ' + d.toLocaleTimeString();
        }

        updateSummary(allPlayers);
        renderTable(allPlayers);
    }

    document.addEventListener('DOMContentLoaded', () => {
        setupSort();
        setupSearch();
        setupUpdateButton();
        loadData();
    });
})();
