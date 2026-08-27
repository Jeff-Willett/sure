# Transaction Explorer performance implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the MyFIN Transaction Explorer spreadsheet-fast for ordinary exploration without weakening financial correctness or storing protected transaction data persistently in the browser.

**Architecture:** First remove the measured Rails N+1 and repeated row construction. Then keep one bounded authorized report dataset in page memory and derive filters, totals, rollups, and Tabulator rows client-side while synchronizing only filter identifiers with browser history.

**Tech stack:** Rails 8.1, Active Record, Minitest, Stimulus, Turbo, Tabulator, JavaScript ES modules, Docker2 isolated preview.

**Spec:** `docs/superpowers/specs/2026-08-27-transaction-explorer-performance-design.md`

## Global constraints

- Work only on `codex/performance-improvements` in this worktree.
- Preserve financial signs, refunds, transfers, totals, entity allocations, reporting profiles, category schemes, tags, permissions, and the shared filtered set.
- Never persist protected transaction rows in browser storage.
- Do not mutate live financial data or deploy to production.
- Deploy only to the isolated Docker2 preview on port 8950.

---

### Task 1: Collapse server report work and restore the grid module

**Files:**
- Modify: `app/services/myfin/entity_category_context.rb`
- Modify: `app/queries/myfin/transaction_explorer/report.rb`
- Modify: `app/javascript/controllers/transaction_explorer_tabulator_controller.js`
- Modify: `test/services/myfin/entity_category_context_test.rb`
- Modify: `test/queries/myfin/transaction_explorer/report_test.rb`
- Create: `test/javascript/controllers/transaction_explorer_tabulator_import_test.mjs`

**Interfaces:**
- Consumes: preloaded `entity.category_schemes`, report `source_rows`, selected entity IDs.
- Produces: category context without per-row scheme SQL, one selected row build per report, and fingerprint-safe logical JavaScript imports.

- [ ] Add a failing test proving preloaded category schemes resolve without another scheme query.
- [ ] Add a failing representative report query-budget test that rejects per-row category-scheme SQL.
- [ ] Add a failing JavaScript source test that rejects the relative view-state import.
- [ ] Resolve the scheme from the loaded association and reuse the selected row set.
- [ ] Change the Tabulator import to the logical import-map path.
- [ ] Run the focused Ruby and JavaScript tests, changed-file lint, and the same Docker2 report benchmark.
- [ ] Deploy the exact commit to port 8950 and verify the grid, filters, console, and failed requests in a browser.
- [ ] Commit and push the coherent checkpoint.

### Task 2: Add a pure in-memory Explorer report engine

**Files:**
- Create: `app/javascript/utils/transaction_explorer_report.mjs`
- Create: `test/javascript/utils/transaction_explorer_report_test.mjs`
- Modify: `app/helpers/myfin/transaction_explorers_helper.rb`
- Modify: `test/helpers/myfin/transaction_explorers_helper_test.rb`

**Interfaces:**
- Consumes: authorized serialized rows, filter catalogs, selected filter identifiers, reporting-profile metadata.
- Produces: `deriveExplorerReport(dataset, filters)` returning visible rows, metrics, rollup, availability, and normalized filters from one row set.

- [ ] Write failing tests for entity, date, type, search, category, tag inclusion/exclusion, refunds, transfers, totals, and rollups.
- [ ] Implement the smallest pure report engine that passes the tests.
- [ ] Extend the serialized row contract only with fields required to preserve current semantics.
- [ ] Prove the engine never touches browser storage or performs network requests.
- [ ] Run focused Ruby and JavaScript tests and review the serialized payload size.

### Task 3: Keep the Explorer workspace alive during ordinary exploration

**Files:**
- Modify: `app/javascript/controllers/transaction_explorer_tabulator_controller.js`
- Modify: `app/javascript/controllers/transaction_explorer_slicer_controller.js`
- Create: `app/javascript/utils/transaction_explorer_history.mjs`
- Create: `test/javascript/utils/transaction_explorer_history_test.mjs`
- Modify: `app/views/myfin/transaction_explorers/_filters.html.erb`
- Modify: `app/views/myfin/transaction_explorers/_rollup.html.erb`
- Modify: `app/views/myfin/transaction_explorers/_tabulator_grid.html.erb`

**Interfaces:**
- Consumes: `deriveExplorerReport`, form controls, rollup drill-down identifiers, current URL.
- Produces: immediate `table.replaceData`, totals and rollup DOM updates, URL synchronization, and `popstate` restoration without an Explorer GET.

- [ ] Write failing history and interaction tests for replace, push, back, forward, and unchanged-input deduplication.
- [ ] Route slicer and search changes to the persistent controller instead of form submission.
- [ ] Update the grid, totals, rollups, filter availability, and selection from one derived report.
- [ ] Preserve layout and non-sensitive filter persistence without storing rows.
- [ ] Verify no document or Turbo-frame request occurs for ordinary exploration.
- [ ] Run focused tests and lint.

### Task 4: Preserve server-authoritative edits in the in-memory view

**Files:**
- Modify: `app/controllers/myfin/transaction_explorer_classifications_controller.rb`
- Modify: `app/controllers/myfin/transaction_explorer_classification_batches_controller.rb`
- Modify: `app/javascript/controllers/transaction_explorer_tabulator_controller.js`
- Modify: corresponding controller and JavaScript tests.

**Interfaces:**
- Consumes: permission-checked classification and tag mutation responses.
- Produces: minimal JSON row patches with conflict status, followed by local report recomputation.

- [ ] Write failing tests for success, stale classification, forbidden access, invalid category, and tag changes.
- [ ] Return the minimal authoritative row patch instead of rebuilding discarded Turbo targets.
- [ ] Apply the patch locally and recompute the visible report.
- [ ] Preserve undo, redo, and audit-history behavior.
- [ ] Run focused controller, service, and JavaScript tests.

### Task 5: Matched browser verification and completion audit

**Files:**
- Verify only unless a test exposes a defect.

**Interfaces:**
- Consumes: final branch commit and the isolated sample-data preview.
- Produces: before-and-after latency, request, query, console, layout, history, and financial-semantic evidence.

- [ ] Deploy the exact branch commit to port 8950 and verify its revision label.
- [ ] Have Luna repeat the representative workflow and record interaction timings, requests, loading states, screenshots, console errors, and failed requests.
- [ ] Verify entity, reporting profile, year, month, type, search, category, tags, selection, drill-down, rollup, back, forward, and layout movement.
- [ ] Verify totals and the ledger derive from the same filtered rows.
- [ ] Run the complete affected Ruby and JavaScript suites plus changed-file lint.
- [ ] Review the diff with GLM and an independent code-review agent, fix important findings, commit, push, and publish the final preview checkpoint.
