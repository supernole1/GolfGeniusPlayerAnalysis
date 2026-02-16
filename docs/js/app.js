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

    async function pollWorkflow(token, btn) {
        const url = `https://api.github.com/repos/${GITHUB_OWNER}/${GITHUB_REPO}/actions/runs?per_page=1&event=workflow_dispatch`;
        const headers = {
            'Authorization': `Bearer ${token}`,
            'Accept': 'application/vnd.github.v3+json'
        };

        let attempts = 0;
        const maxAttempts = 60; // 10 minutes max

        const poll = setInterval(async () => {
            attempts++;
            try {
                const resp = await fetch(url, { headers });
                const data = await resp.json();
                const run = data.workflow_runs && data.workflow_runs[0];

                if (!run) return;

                const status = run.status;
                const conclusion = run.conclusion;

                if (status === 'completed') {
                    clearInterval(poll);
                    if (conclusion === 'success') {
                        btn.textContent = 'Done! Reloading...';
                        setTimeout(() => window.location.reload(), 2000);
                    } else {
                        btn.textContent = 'Update Standings';
                        btn.disabled = false;
                        alert('Scraper finished with status: ' + conclusion + '\nCheck the Actions tab on GitHub for details.');
                    }
                } else {
                    btn.textContent = 'Scraping... (' + Math.floor(attempts * 10 / 60) + 'm)';
                }
            } catch (e) { /* ignore poll errors */ }

            if (attempts >= maxAttempts) {
                clearInterval(poll);
                btn.textContent = 'Update Standings';
                btn.disabled = false;
                alert('Timed out waiting for scraper. Check the Actions tab on GitHub.');
            }
        }, 10000); // poll every 10 seconds
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
