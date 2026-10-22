# Production barriers

The goal of a study is a clone that can run in production. Screens and rules are not enough: some features depend on approvals, licenses, certifications or assets the clone does not have. This file says what to look for, where, and how to record it in `clone/barriers.md`.

This is not legal advice. Record what the source says. A legal reading of your own is `[inf]` with a `Q-###` addressed to counsel.

## Set the target market first

Barriers depend on where the clone will run and whom it will serve. Fill "Clone target market" in `00-charter.md` (country or region, customer segment, company size) before the barrier scan. When the user did not say, assume the user's own country and segment and write the assumption there.

## Categories

| Category | What to look for | Typical gatekeepers and examples |
|---|---|---|
| Permissioned integrations | Each integration the product offers whose API requires approval, a partner program, a security review or a paid tier | Google OAuth verification (security assessment for restricted scopes); Microsoft publisher verification; Slack Marketplace review; Meta WhatsApp Business Platform (business verification, template approval, per-message pricing); LinkedIn partner programs; app marketplaces of the integrated product |
| Regulation and licensing | Activities that need a license or authorization in the target market, and data rules | Payments, banking, credit, insurance, health, telecom, education; in Brazil: Open Finance and Pix participation (Central Bank), electronic invoices (state tax authority credentialing and an ICP-Brasil certificate), e-signature validity rules; data protection laws (LGPD, GDPR); AI-specific rules where they apply |
| Certifications buyers require | What the product's customers will ask before buying | SOC 2, ISO 27001, PCI DSS for card data, HIPAA agreements; enterprise requirements such as SSO, SCIM, audit logs, data processing agreements, data residency |
| Distribution gatekeepers | Channels that review or limit the product | Apple App Store and Google Play review; browser extension stores; bulk email sender rules (authentication, unsubscribe, spam rate); SMS sender registration |
| Data, content and network effects | What users get from the product that code cannot copy, and what it takes to switch | Template libraries, integrations count, marketplaces, community content, historical data, models trained on customer data, other users already on the platform; how complete the product's exports are and what importers the clone needs |
| Intellectual property and terms | What the clone must not copy | Trademarks and product names, icons, illustrations, documentation text, patents the product cites; the product's terms on reverse engineering and competing use |
| Infrastructure and operating cost | What is costly or slow to match | Realtime collaboration at scale, offline sync, uptime commitments, multi-region hosting, per-use fees of third-party services the feature depends on |
| The clone's own operation | What the clone needs to sell in the target market | Recurring billing methods customers expect, invoices and taxes for software sales, a data protection officer, local hosting if required |

## Where to look

Use web search and web fetch, as in recon. Add each source to `sources.md`.

| Source | Reveals |
|---|---|
| Integrations page or app marketplace of the product | The integration list; check each provider's developer docs for approval steps |
| Subprocessors list (often linked from the privacy policy or DPA) | Third-party vendors the product depends on |
| Security or trust page | Certifications held and promised |
| Pricing page | Features held back for enterprise plans, often because they carry compliance work |
| Terms, privacy policy, DPA | Data roles, retention, residency, competing-use clauses |
| Provider developer docs (Google, Meta, Slack, payment and banking providers) | The approval process, its requirements, published review times and fees |
| Regulator sites in the target market | Licenses, authorizations, registration steps |
| `inventory.js` third-party SDK list and network origins | Vendors visible in the product's own pages |
| The product's OAuth consent screens (open, record, cancel; never approve) | The exact scopes each integration requests, which decide the verification level |

## Recording a barrier

One section per barrier in `clone/barriers.md`. IDs `BR-###`.

```markdown
### BR-003 WhatsApp messages need Meta business verification
- Category: permissioned integration
- Blocks: F-014 (WhatsApp notifications)
- Gatekeeper: Meta, WhatsApp Business Platform
- Severity: blocks feature
- Market weight: required to sell (buyers in the target market expect WhatsApp in a CRM) [inf] Q-040
- What it takes: business verification, a phone number on the platform, approved message templates, per-message fees
- Lead time and cost: [doc SRC-021]
- Mitigation: start verification in month one; launch with email notifications until approved
- Evidence: [doc SRC-021]
```

Severity values:

| Severity | Meaning |
|---|---|
| `blocks launch` | The clone cannot go live in the target market until it is cleared |
| `blocks feature` | One feature waits; the rest can launch |
| `adds lead time` | Cleared by a process with a waiting period; start it early |
| `adds cost` | Cleared by paying (certification, fees, a licensed partner) |
| `moat` | The clone can launch but will not match it soon (data, network, content) |

Severity says what the barrier blocks. Market weight says how much that matters to buyers in the target market: `required to sell`, `important`, `minor`. A barrier that only blocks one feature is a launch problem when that feature is required to sell; order the PRD by both.

Every barrier cites evidence, like a rule. Interpretations without a source are `[inf]` with a `Q-###`.

Record the official route for each integration. Unofficial routes (scraping, automating another product's web app) can get accounts banned and do not clear a barrier; name them only as a risk.

Approval rules, fees and review times change. Each barrier keeps the date its source was read (`sources.md`), and the PRD treats sources older than six months as needing a recheck.

## Using barriers in the synthesis

- `clone/prd.md`: list launch blockers first; mark features that wait for a barrier; put long lead-time approvals at the start of the build order.
- `inventory/features.md`: add the `BR-###` of each barrier to the features it affects.
- When a licensed partner removes a barrier (a payments provider, a banking-as-a-service platform, a WhatsApp solution provider), record the partner option and its cost in "Mitigation".
