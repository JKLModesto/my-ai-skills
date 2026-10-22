# Safety procedures

SKILL.md holds the rules (levels, action classes, write gate, stop list). This file holds the procedures.

## Setting up each level

### L1 Dedicated account (best)

The user does these steps; the agent writes them under "Needs human" in `STATUS.md` when they are missing.

1. Sign up for a trial or sandbox with an address the user owns (for example `name+re-product@domain`). Some products sell sandbox accounts on higher plans (Pipedrive, Salesforce, HubSpot); prefer them when available.
2. Create a separate browser profile used only for this study, and log in there. The production account must not be logged in on that profile.
3. Connect the agent's browser tool to that profile (see `tools.md`).
4. Record in `environment.md`: account email, workspace name, plan, trial end date, profile name.

A separate profile is the strongest guard: the agent cannot reach production even by mistake.

Note the trial end date. Plan-gated features must be studied before it.

### L2 Separate workspace

1. Write the ledger row first (class A4, action `create`).
2. Confirm creation is free: no payment form, no plan choice that starts billing, no terms to accept. If any appears, cancel and fall back to L3.
3. Name it `🧪 [RE] <Product> study`.
4. Skip invites, "connect apps", imports, AI offers and trial offers.
5. Record its name, URL and ID, and the production workspace's name and ID as "never write here" identifiers.

Expected side effects, each with a ledger row:

- The product switches the user's last-used or default workspace (A3; restore it at session end).
- Onboarding creates default content (spaces, sample tasks) inside the new workspace (A2).
- Welcome or tips emails go to the operator. This is acceptable; note it in `STATUS.md`.

The user's personal settings (profile, notification preferences, theme) are shared across workspaces. A3 rules still apply.

A new workspace usually starts on the free plan while production may run on a paid one. Mark features the free plan lacks as `blocked: plan` in coverage and add "Start a trial in the test workspace?" under "Needs human". Starting a trial is A5. When a trial is running, study plan-gated features before it ends, ahead of the normal priority order.

### L3 Sandbox container

1. Pick the most private place the product offers: a personal space, a private project, a pipeline restricted to the operator.
2. If the container cannot be private (the product has no such option, or making it private is A4, such as adding a visibility group), hide the records instead: set each record's own visibility to the operator only ("owner only", "private", "only me") where the product offers it. Check it from the record list, and record it in `environment.md`.
3. Name it `🧪 [RE] Sandbox`.
4. Record the full breadcrumb, URL and ID. The write gate compares the screen against this.
5. Inherited configuration (statuses, tags, custom fields defined above the container) is read-only. Create new fields at container level only, and only when the product offers that scope explicitly.
6. Note who can see the container and the records. A pipeline or project visible to the whole company is acceptable only with fake data and the `[RE]` prefix, and with records hidden as in step 2 when the product allows it.

### L4 Observe only

A0 and A1 only. Use L4 for production screens that cannot be reproduced in the sandbox (real volume, real configuration). Mask personal data before every screenshot.

## Preflight checklist

Run before the first write at L2 or L3. Record each answer in `environment.md`.

| Check | Where to look | Write allowed if |
|---|---|---|
| Members | Workspace members or users page | At L3: count noted; nobody will be assigned or mentioned |
| Automations | Automations, workflows, rules pages; container-level automations | None active that triggers on records in the write scope |
| Webhooks and API apps | Developer, webhooks, apps or marketplace pages | None that would receive events from the write scope |
| Integrations | Slack, Teams, email, calendar, Zapier, Make | None posting from the write scope |
| Email and calendar sync | Personal and company sync settings | Off, or the records created have no attendees or recipients |
| Plan and trial | Billing page (read only) | Plan known; trial end date noted |
| Baseline counts | Records of each main type in the container, and the operator's records added or changed since the first ledger row: a list view filtered by owner and date, or a count endpoint (GET only) | Counts and the filters used recorded for comparison at close |

Count only what the study can change. Totals for the whole account drift while the team works, so teardown could not explain the differences. Do not pull full record lists through an API connector to count them: they bring real customer data into the agent's context. Prefer a filter, or an endpoint that returns a total without the records (a summary or count endpoint, or a total in the pagination data).

If an automation would fire on sandbox records, choose another container or stay at L4 for that feature.

## Ledger

`sandbox/ledger.csv`, one row per change. Columns:

| Column | Content |
|---|---|
| `id` | `L-001`, sequential |
| `time` | ISO timestamp |
| `class` | A1, A2, A3, A4, or `incident` |
| `action` | `create`, `update`, `delete`, `toggle`, `incident` |
| `object` | Type and name, for example `task "[RE] overdue"` |
| `location` | Breadcrumb or URL |
| `object_id` | Product ID when known |
| `before` | Previous value for updates and A3 changes; empty for creates |
| `undo` | How to reverse it |
| `status` | `open`, `restored`, `removed`, `fixture`, `kept`, `human` |
| `note` | Required for `fixture`, `kept`, `human` and `incident` |

Rules:

- Write the row before the action, or immediately after if the ID only exists after creation.
- One row can cover a batch of identical fixtures (`object` = `12 tasks "[RE] f-01..f-12"`).
- A1 changes need a row only when they risk persisting (view drafts, filters on a saved view).
- `fixture` means it stays for the next session as test data. `kept` means the user decided to keep it after the study. `human` means only the user can resolve it (an undo that would notify someone, a shared setting with an unknown before-value); the note says what the user should do. `check-kb --closing` fails on `open`, `fixture` and `human`.
- A change with an unknown before-value that affects only the operator (a layout toggle): leave it, status `human`, and note the setting so the user can reset it.
- An automation gets one row for itself and a note on what it creates ("creates tasks named [RE] auto-*"). At teardown, search for those records too.
- Time-triggered automations are disabled at the end of every session (ledger note `disabled`).

## Teardown

At the end of each session: restore every A1 and A3 row, and disable time-triggered automations. At the end of the study: remove every A2 and A4 row. At L3 with a container other members can see: remove every A2 row at the end of each session too.

1. Work from the ledger, newest first, so dependents go before their parents.
2. Delete through the product's own controls. Prefer deleting the container when everything inside it belongs to the study.
3. Verify each removal: reload, search for the `[RE]` prefix, check trash or "restore data" pages.
4. Look for orphans. Deleting a parent can leave children behind (activities, notes, comments, attachments, time entries). Search for them by the `[RE]` prefix and by date.
5. Count again with the baseline filters: the container, and the operator's records added or changed since the first ledger row. Each record still there must match a ledger row marked `kept`, or a residual. Explain every other difference.
6. List residuals in `STATUS.md` (for example "a note attached to a deleted deal; no UI to delete it").
7. Run `check-kb --closing`. It fails while any ledger row is `open`, `fixture` or `human`.

Trash retention (often 30 days) means a removed item is still restorable. State this in `STATUS.md`.

## Incidents

When something goes wrong:

1. Check whether the undo itself reaches anyone. Unassigning a person, deleting a comment that mentions them, or reverting a shared record can notify them again.
2. If the undo reaches nobody, undo at once (toast, Ctrl+Z, "restore").
3. If it would reach someone, do not undo. Write it under "Needs human" so the user decides.
4. Add a ledger row with class `incident`: what happened, who could have seen it, what was undone, what remains.
5. If a real person may have been notified, add under "Needs human" the exact wording the user can send them.
6. A saved change to a shared view or setting whose before-value you do not know: do not rebuild it from memory. Record the incident with what you changed and ask the user, through "Needs human", to check it.
7. Do not hide or minimize it in the session log.

## Adopting an unrecorded session

When a session made changes without this skill (no ledger, findings only in context):

1. Create the KB if missing (`init-kb.mjs`).
2. Write a ledger row for every change you know of. Write `unknown` in `before` when the previous value is not known. Do this before touching anything.
3. Undo what affects other people, following "Incidents".
4. Screenshots that exist as files: move them, unreviewed, to a quarantine folder outside the KB and outside git, and note its path in `STATUS.md`. A later review moves clean ones into `evidence/` with `EV-###` names and deletes permanently (not to the trash) those that show personal data. Screenshots that were never saved as files are lost; say so in the log.
5. Write findings as `Q-###` "Confirm: ..." entries, not as rules: they lack evidence.
6. Mark the environment preflight as "not run" in `environment.md` and run it before the next write. Removing records you created does not need the preflight, provided the removal notifies nobody (records assigned to or mentioning other people go to `human`).
7. A custom field you created whose scope is unknown: check its scope first. Delete it as teardown only if no record outside the sandbox holds a value in it; otherwise status `human`.

## Hidden writes: examples

| Pattern | Seen in |
|---|---|
| View changes are drafts until "Save view"; the draft is lost on reload | ClickUp |
| A layout toggle in a task changes the user's global preference | ClickUp |
| Completing the last open activity opens a "schedule next activity" dialog | Pipedrive |
| Deleting deals leaves their activities in place | Pipedrive |
| Notes attached to deleted records become unreachable in the UI | Pipedrive |
| Inline fields save on blur, with no Save button | Most products |
| Opening the inbox marks notifications as read | Most products |

Add new patterns to `topics/hidden-writes.md` in the KB when found.
