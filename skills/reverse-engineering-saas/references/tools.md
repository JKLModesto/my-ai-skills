# Browser tools

The skill needs six capabilities: navigate and act, screenshot to a file, read the accessibility tree, run JavaScript in the page, read network requests, and resize the window. Use the tool that reaches the right browser profile.

| Capability | Claude in Chrome (`mcp__claude-in-chrome__*`) | Playwright MCP (`browser_*`) | Chrome DevTools MCP | Computer use |
|---|---|---|---|---|
| Uses the user's logins | Yes, the profile where the extension runs | Only its own profile, after the user logs in there | Yes, if attached to the user's Chrome | Yes, whatever is on screen |
| Act | `computer`, `form_input`, `navigate` | `browser_click`, `browser_type`, `browser_navigate` | `click`, `fill`, `navigate_page` | Clicks and keys |
| Screenshot to file | `computer` screenshot with `save_to_disk: true`; no path is returned (see "Claude in Chrome notes") | `browser_take_screenshot` with `filename` | `take_screenshot` with a file path | Screenshot, then save |
| Accessibility tree | `read_page` | `browser_snapshot` | `take_snapshot` | No |
| JavaScript | `javascript_tool` | `browser_evaluate`, `browser_run_code_unsafe` | `evaluate_script` | No |
| Network list | `read_network_requests` | `browser_network_requests` | `list_network_requests` | No |
| Real drag | Limited | `browser_drag` | `drag` | Yes |

Tool names change between versions. Check the tools actually present in the session.

## Claude in Chrome notes

Seen in real studies. Check them again with the version you have.

- **Long results.** `javascript_tool` cuts its output near 1,000 characters, so a full `inventory.js` or `api-shapes.js` result does not come back. Write the JSON into an offscreen `<article>` at the top of the body and read it with `get_page_text`, which reads `<article>` first:
  ```js
  const out = document.getElementById('__re-out') || document.body.insertAdjacentElement('afterbegin', Object.assign(document.createElement('article'), { id: '__re-out' }));
  out.style.cssText = 'position:fixed;left:-10000px;top:0;width:800px';
  out.textContent = JSON.stringify(window.__re.last);
  ```
  Save what `get_page_text` returns, then remove the element (`document.getElementById('__re-out').remove()`).
- **Network list.** `read_network_requests` can miss the app's own API calls; in one study it listed only telemetry. Install `api-shapes.js` and use `__re.api.dump()`. Use the network list as a cross-check only.
- **No local servers.** Never load page scripts or any file from `localhost` or `127.0.0.1` in the user's tab. Chrome holds the request behind a "local network access" permission prompt in the user's browser, which the agent cannot see and must not answer. Paste the file content instead. If it happened: reload the tab, which dismisses the prompt without a decision, and add an `incident` ledger row.
- **Background windows.** In a window that is not in front, the first click is often ignored, and menus toggle on each click. After each click, check the state at once (`read_page` or a screenshot) before clicking again.
- **Saving screenshots.** `computer` screenshot with `save_to_disk: true` returns no path. In Claude Code the file lands in the session's `tool-results/` folder (`~/.claude/projects/<project>/<session>/tool-results/mcp-claude-in-chrome-blob-*.jpg`). Copy the newest file there to `evidence/` right after the capture. When a capture shows unmasked data, delete that file too.

## Choosing

- **L1 dedicated account:** the separate profile is the guard. Use Playwright MCP with a persistent profile directory that only holds the trial login, or Claude in Chrome installed in a separate Chrome profile.
- **L2 to L4 (user's own login):** Claude in Chrome in the user's Chrome. Open a new tab for the study; do not act on the user's existing tabs.
- **Desktop apps:** limited. Computer use gives screenshots and clicks only, with no DOM or network access, so most of this skill does not apply. Prefer the product's web app.
- **Built-in app browsers** (for example the Claude desktop browser pane) have no user logins and may ask for approval per site. Use them only for local files and public pages.

## Separate profile for L1

The user does this once:

- Chrome: Profile menu → Add → name it `RE <Product>`. Install the agent's browser extension in that profile, log in to the trial account there, and use only that window for the study.
- Playwright MCP: start it with a dedicated user data directory (for example `--user-data-dir ~/.re-profiles/<product>`), open the product, and let the user log in once. The session persists across runs.

Record the profile name in `environment.md`.

## Window size

In a dedicated profile (L1) or a browser only the agent uses, set a fixed size at the start (1440 × 900) and record it. Change it only for responsive checks, then restore it.

In the user's own Chrome, do not resize a window the user may be using (a call, other work). Record the current viewport in `environment.md` and use it for every screenshot. Responsive checks wait for a moment the user is away, or go to "Needs human".

## Public sources

Read documentation, API references, pricing and changelogs with web search and web fetch, not with the agent's browser. This keeps the logged-in browser for the product and avoids per-site approval prompts.
