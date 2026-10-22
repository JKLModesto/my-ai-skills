# Extraction techniques

## Running the page scripts

Read the script file and pass its full content to the browser's JavaScript tool (`javascript_tool`, `browser_evaluate`, `evaluate_script`). Each script attaches functions to `window.__re` and returns a JSON-serializable result. Save the result as `evidence/EV-###-<script>-<screen>.json`.

A reload clears `window.__re`. Run the script again after every reload or full navigation. Never load the scripts from a local server in the user's browser; paste them (`tools.md`).

When the tool cuts long results (Claude in Chrome does near 1,000 characters), read them through the page instead: `tools.md`, "Claude in Chrome notes".

Playwright MCP's `browser_evaluate` expects a function. Wrap the file content: `() => { <file content>; return window.__re.last; }`. Every script stores its latest result in `window.__re.last`.

| Script | Call | Notes |
|---|---|---|
| `inventory.js` | Runs on load; `__re.inventory()` reruns | Run on each main screen. Large pages: results are capped and say so |
| `tokens.js` | Runs on load; `__re.tokens({root: '.selector'})` limits to a subtree | Run once per theme. Diff light and dark to find themed tokens |
| `api-shapes.js` | Installs on load; `__re.api.dump()`, `__re.api.clear()` | Install, clear, perform one action, dump. Records shapes, never headers; keeps short enum-like values of status and type fields unless `__re.api.enumSamples = false` |
| `mask.js` | `__re.mask.apply({selectors: [...], names: [...], avatars: true, placeholders: true})`, `__re.mask.clear()` | Blurs emails, phones, money values, Brazilian tax IDs (CPF, CNPJ), small avatars, the given names, placeholders that match, and the given selectors. Selectors and `placeholders: true` stay as CSS rules until `clear()`. See "Masking" |
| `annotate.js` | `__re.annotate(['.header', '.toolbar', ...])`, `__re.annotate.clear()` | Numbered outlines; the result lists number, selector, size |

## Design tokens

1. `tokens.js` lists CSS custom properties from readable stylesheets and from `:root`, then counts computed values across visible elements: text and background colors, border colors, font families, sizes, weights, line heights, radii, shadows, gaps and paddings.
2. A value used by many elements and equal to a CSS variable gets that variable's name as its token name.
3. For a single component, call `__re.tokens({root: '<selector>'})` and record the result in the component file.
4. Hover, focus and pressed states: hold the state (hover with the mouse, focus with Tab), then call `tokens` on that element. Take a zoomed screenshot.
5. Fonts: the `fonts` field lists loaded font faces. Icons: record names and sizes from SVG `<use>` references and class names. Do not copy icon files into the clone.
6. Motion: computed `transition` and `animation` values are in the component output. For animations that values do not explain (drag previews, panels sliding), record a short GIF or video when the tool can (Claude in Chrome `gif_creator`) and save it as evidence.
7. Icons: list them in `design/tokens.md` under "Icons" (name, size, where used). Names come from SVG `<use href="#name">`, class names or `aria-label`.

## Component names

Production bundles shorten JavaScript names, but other sources keep them:

| Source | Example |
|---|---|
| Custom element tags (Angular, Web Components) | `cu-board-task`, `cu-dates-field` |
| Test and analytics attributes | `data-testid="deal-card"`, `data-test`, `data-qa`, `data-cy`, `data-pendo-id` |
| Class name prefixes of design systems | `MuiButton-root`, `ant-select`, `chakra-`, `data-radix-*` |
| ARIA roles and names | `role="dialog" aria-label="Schedule next activity"` |
| Source maps, when public | Original file and component names (rare in production) |

`inventory.js` collects the first four. Use the product's own names as aliases in `C-###` files; give each component a neutral name for the clone.

## Data model

Combine three sources and tag each field with the strongest:

1. Public API reference: `[doc SRC-###]`.
2. Network shapes from `api-shapes.js`: `[net EV-###]`. The recorder reports types and format hints (`iso-date`, `epoch-ms`, `uuid`, `email`, `url`, `hex-color`) and, for status and type fields, short enum-like values.
3. UI: field types seen in forms and custom field menus: `[obs EV-###]`.

Vary fixtures to reveal every field: one record per custom field type, with and without optional values, with relations.

For enums (statuses, priorities, activity types), read the options from the UI menus and record them in the entity file.

## Network

- `api-shapes.js` wraps `fetch` and `XMLHttpRequest` after installation. It misses requests made before installation and requests from clients that saved a reference to `fetch` at startup. When it misses traffic, use the browser tool's network list (`read_network_requests`, `browser_network_requests`, `list_network_requests`) and record method, URL template and status.
- GraphQL: the recorder keys entries by `operationName`.
- WebSocket: the recorder wraps sockets opened after installation and records message shapes. Most apps open their socket at startup, before the script runs. To capture those frames, the script must run before the app starts: with Playwright, add it as an init script (`page.addInitScript`) and reload. With other tools, record realtime as UI behavior (a second tab updates without reload) and tag it `[obs]`.
- Never save headers, cookies, tokens or response values. Endpoint templates replace IDs with `:id`.

## Screenshots

- Name: `EV-###-<screen>-<state>.png`.
- Mask personal data first at L3 and L4.
- Anatomy: run `annotate.js` with the region selectors, capture, then clear.
- Use one window size for every screenshot, recorded in `environment.md`. When to resize and when not: `tools.md`.
- How to write the file depends on the tool: see `tools.md`.

## Masking

- Patterns, names and avatars mark what is on the page when `apply()` runs. Content rendered later (popovers, dropdowns, a list that loads after a form opens, a re-render) is not marked: run `apply()` again right before each screenshot.
- Selectors become CSS rules that blur matching elements whenever they appear, until `clear()`. Pass the containers that show real data: popovers, menus, lists (`[role=listbox]`, `[role=menu]`, the product's popover class from `read_page` or `inventory.js`). Rules add up across calls; `result.rules` counts them and `result.invalidSelectors` lists the ones rejected.
- Company configuration (activity type names, lost reasons, custom field labels, pipeline and user names) matches no pattern. Pass the values as `names`, their containers as `selectors`, or crop the screenshot to the part under study.
- Inputs: values and placeholders that match a pattern are blurred. `placeholders: true` blurs every placeholder, in fields rendered later too; use it when placeholders show configuration or names.
- Look at each screenshot before saving it. One that shows unmasked data is deleted at once, with the tool's own copy (`tools.md`), and retaken.

## Drag and drop

Many drag libraries (Angular CDK, dnd-kit, react-beautiful-dnd) ignore synthetic events and fast automated drags.

1. Try the tool's real drag with intermediate steps (Playwright `browser_drag`, or mouse down, several moves, mouse up).
2. If nothing moves, record the DOM structure: drag handles, drop zones, and what the drop changes (the grouping value). Mark interaction `blocked: drag not automatable`.
3. In attended mode, ask the user to perform the drag while you observe and capture.

## Persistence and storage

- After each change: reload and compare.
- `inventory.js` lists `localStorage` and `sessionStorage` key names (not values). A key that changes after an action shows browser-side persistence.
- URL query parameters that change with filters show URL-scoped state.
