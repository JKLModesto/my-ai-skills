# Exploration method

## Phase 1: Charter

Fill `00-charter.md` from the user's request. Decide without asking when the request is silent:

| Item | Default |
|---|---|
| Goal | Rebuild the product's core loop well enough to replace it for the user's team |
| Scope | Features the user named, then the core loop (the screens a daily user opens every day) |
| Depth | Rebuild grade: anatomy, states, rules, data model, API shapes |
| Clone target market | The user's own country and customer segment; write the assumption |
| Mode | Unattended if the user said not to ask or will be away; otherwise attended |
| Environment | Per SKILL.md "Environment levels" |
| Language | KB prose in the user's language |

Record the product's terms on reverse engineering (search the terms page for "reverse", "copy", "scrape", "benchmark") with the URL.

## Phase 2: Environment and preflight

Follow `safety.md`: choose the level, set it up, run the preflight checklist, record baseline counts, fill `sandbox/environment.md`. No write before the preflight passes.

## Phase 3: Recon from public sources

Use web search and web fetch, not the agent's browser. Record each source as `SRC-###` in `sources.md` with the date read.

| Source | What it gives |
|---|---|
| Help center table of contents | The feature tree: the vendor's own taxonomy of features. Seed `inventory/features.md` from it |
| API reference (REST, GraphQL, OpenAPI file) | Entities, fields, types, enums, limits, error codes, pagination, webhooks events. Seed `data-model/` |
| Changelog and release notes | Recent features, names of features behind flags, deprecations |
| Pricing page | Plan gating per feature, seat model, limits |
| Templates gallery | Real use cases and default configurations |
| Status page | Service components (hints of architecture) |
| Keyboard shortcut page | Full shortcut list |
| Community, reviews, Reddit | Pain points and missing features (input for "improve") |
| Security and trust page | Data residency, SSO, audit log, permissions model |

Run the barrier scan in the same pass: integrations list, subprocessors, security page, terms, and the developer docs of each permissioned integration. Record barriers in `clone/barriers.md` (`references/barriers.md`).

Tag every claim from these as `[doc SRC-###]`. A documented behavior still needs observation before it becomes a rule the clone depends on, unless it cannot be observed (then keep `[doc]` and say so).

## Phase 4: Map

1. Walk the navigation: every top-level area, settings page, and "+ New" menu. One `S-###` per distinct screen in `inventory/screens.md`, with its URL pattern (IDs replaced by `:id`).
2. Run `inventory.js` on each main screen. Its `routes` list finds screens not reachable from the visible navigation.
3. Run `tokens.js` once per theme on a representative screen. Save the output as evidence.
4. Link features to screens. Fill `inventory/coverage.md` with one row per feature, in priority order.

### Priority order

1. P1: features the user named.
2. P2: the core loop: create, view, edit, complete the main object (task, deal) and the main views (list, board).
3. P3: data model completeness: every field type, every relation.
4. P4: collaboration, notifications, permissions (often need L1 and a second account).
5. P5: settings, admin, billing, integrations.

Exception: when a trial is running, plan-gated features come before its end date.

### Screens, views and overlays

- A screen is anything with its own URL pattern: each view type of a container (list, board, calendar) is a separate screen; a task or deal page that opens as a modal with its own URL (`/t/:id`) is a screen.
- A modal, popover or panel without its own URL is a component, linked from the screens that open it.

## Phase 5: Deep dive

### Per-screen checklist

| Aspect | Record |
|---|---|
| Purpose and entry points | How the user gets here; URL pattern |
| Anatomy | Regions in order, with an annotated screenshot (`annotate.js`) |
| Components | Each reusable piece, linked to `C-###` |
| Data shown | Which entity and field feeds each element |
| States | Empty, loading (skeleton or spinner), typical, many items (pagination or virtual scroll), long text, error, no permission, plan-gated |
| Interactions | Click, double click, hover, right click, drag, inline edit, bulk select, undo |
| Keyboard | Tab order, arrow keys, shortcuts, focus visibility, Escape behavior |
| Accessibility | Roles and names from the accessibility tree; missing labels |
| Microcopy | Labels, placeholders, tooltips, empty states, errors, confirmations (reference only) |
| Persistence | Scope of each change (user, view, container, workspace, URL, browser storage) |
| Realtime | Does a change appear in a second tab without reload? |
| Responsive | Behavior at 1440, 1024 and 390 px widths |
| Motion | Transitions and animations: computed values from `tokens.js`, plus a short GIF or video when the tool can record one |
| Performance as perceived | Skeletons, optimistic updates, delays the user sees |
| Not tested | Everything skipped, with the reason |

### Fixture design

Plan fixtures before creating them. One record per case, named for the case:

| Case | Example name |
|---|---|
| Empty or minimal | `[RE] minimal` (only required fields) |
| Typical | `[RE] typical` |
| Every field filled | `[RE] all fields` |
| Long text and unicode | `[RE] long title with émoji 🚀 and 200+ characters ...` |
| Time states | `[RE] overdue`, `[RE] due today`, `[RE] due next week`, `[RE] no date` |
| Volume | 50+ records for pagination and virtual scroll (batch, one ledger row) |
| Relations | Parent and child, dependency, link, attachment |
| Lifecycle | One per status, one won, one lost, one archived, one deleted |

If an API connector or CLI for the product is already configured for the user, use it for bulk fixtures. Create through the UI the records whose creation is the behavior under study.

### Probing rules

Change one input at a time. Record each probe as a row: case, input, result, evidence. Useful variations:

- Boundaries: 0, 1, many, the maximum length, the maximum count.
- Dates: past, today, future, no time versus time, weekends, time zones, recurrence.
- Required fields: leave each one empty; check when validation fires (on blur, on save, on stage change).
- Deletion with dependents: what happens to children, links, history.
- Order of operations: edit A then B versus B then A.
- Undo: is there an undo, for how long, what does it restore.
- Concurrency: the same record edited in two tabs.
- Permissions: the same action as a lower role (L1 with a second account only).

A confirmed behavior becomes a rule:

```markdown
### R-014 Completing the last open activity prompts for the next one
- Given a deal with exactly one open activity
- When the user marks that activity done
- Then a "Schedule next activity" dialog opens; Cancel closes it and the deal shows a warning icon
- Evidence: [obs EV-031, EV-032]
- Feature: F-007 · Screen: S-004
```

### Persistence scopes

After every change, reload. Then classify it:

| Scope | Test |
|---|---|
| Unsaved draft | Gone after reload |
| URL | Survives reload, gone when the URL is opened clean |
| Browser storage | Survives reload, gone in a private window (check `localStorage` key names) |
| User preference | Same in every view and container |
| View | Only in that view |
| Container or workspace | Visible to other members (verify with a second account at L1 only) |

## Cross-cutting topics

Each gets a file in `topics/` when explored:

search, notifications (in-app, email, push: from docs when not observable), developer platform (public API, OAuth apps, webhooks, marketplace review: a clone of an ecosystem must rebuild it), permissions and roles, settings and their scopes, import and export, integrations, automations, AI features, onboarding and empty-state education, plan gating and limits, trash and restore, history and audit log, sharing and public links, templates, time zones and locale, currency and number formats, keyboard shortcuts, offline behavior, mobile and responsive, hidden writes.

## Phase 6: Synthesis

| File | Content |
|---|---|
| `data-model/erd.mmd` | Mermaid ER diagram of all `E-###` |
| `data-model/types.ts` | TypeScript types for every entity, with enums |
| `data-model/permissions.md` | Role × action matrix |
| `design/tokens.md` | Consolidated tokens: color, type, spacing, radius, shadow, motion, z-index, breakpoints |
| `clone/prd.md` | Product requirements for the clone: scope, users, core loop, feature list with priority, non-goals |
| `clone/parity.md` | One acceptance test per `R-###` the clone must pass, grouped by feature |
| `clone/barriers.md` | Every `BR-###` with severity, lead time, cost and mitigation, launch blockers first |
| `clone/implications.md` | For each area: copy, avoid (problems in `findings.md`), improve |

The PRD states the build order: long lead-time approvals and launch blockers first (they run while the team builds), then data model, core loop screens, rules from `parity.md`, then secondary features.

### Depth when writes are not allowed

A feature that could only be read (A4 at L3, L4) is documented from settings pages, editors opened and cancelled, and public docs. Mark its coverage `partial` with the note "read only, not exercised", and say so in the `STATUS.md` summary so the user knows what was observed and what was not.

### Re-verification

Rules in P1 and P2 should rest on two pieces of evidence: two methods (`obs` and `net`) or two sessions. When a later session reproduces a claim, add the new evidence ID to it. When the product changes a behavior, keep the old rule, mark it `superseded`, and add the new one.

## Phase 7: Close

Follow "Close a session" in SKILL.md and "Teardown" in `safety.md`. The `STATUS.md` summary states, in three lines: what was covered, what was not and why, and what the user must decide.
