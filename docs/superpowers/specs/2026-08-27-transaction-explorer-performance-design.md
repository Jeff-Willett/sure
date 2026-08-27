# Transaction Explorer performance design

## Status

Approved by Jeff Willett on 2026-08-27. Non-production preview deployment is authorized. Production deployment, production-data copying, live financial-data mutation, schema changes, and image changes are not authorized.

## Goal

Make ordinary Transaction Explorer interaction feel spreadsheet-fast while preserving the existing financial calculations, filters, rollups, classifications, tags, reporting profiles, entity scoping, selection, layout, persistence, and browser history behavior.

## Measured baseline

The isolated Docker2 preview at commit `b3ebe09c` showed:

- 5.7 to 6.5 seconds to construct the default 22-row report.
- 5,661 SQL queries per report.
- 5,636 repeated category-scheme queries caused by resolving the same preloaded entity schemes for every source row and every row-building pass.
- 7.8 seconds from preview sign-in to the rendered Explorer.
- Every filter and rollup drill-down submits the full form into a Turbo frame, rebuilds the Rails report, replaces the workspace, destroys Tabulator, parses the row payload again, and constructs a new grid.
- The Tabulator controller does not currently load in the built preview because a relative JavaScript import bypasses the fingerprinted asset mapping.

## Design

### Server report

The report continues to own authorization, source loading, financial normalization, entity allocation, category context, totals, and rollups. It must resolve category schemes from already-loaded associations, build the selected entity row set once, and reuse it for filtering and category availability. A focused query-budget regression test protects the representative report from returning to per-row SQL.

### Browser working set

After the server report is within budget, the initial Explorer response will contain one bounded, authorized working dataset plus filter catalogs. A dedicated client module will derive the visible rows, totals, rollups, and availability from that same in-memory array. It will update the existing Tabulator instance instead of replacing the workspace.

Financial rows remain in page memory only. The application must not write transaction rows, amounts, descriptions, accounts, categories, or tags to `localStorage`, `sessionStorage`, or IndexedDB. Existing storage may retain non-sensitive layout settings, slicer modes, and filter identifiers.

### Navigation and mutations

Filtering, searching, selection, drill-down, rollup, and returning to a prior Explorer state will update the in-memory view immediately. The controller will mirror shareable filter identifiers into the URL with `history.pushState` or `history.replaceState` and restore them on `popstate` without fetching the report again.

Classification and tag mutations remain server-authoritative and permission checked. Successful responses update the affected in-memory row and recompute the visible set. Stale, forbidden, or invalid mutations keep the existing conflict behavior and never weaken financial correctness.

## Verification

Each slice requires a red-green regression test, focused Ruby and JavaScript tests, lint for changed files, an exact-commit Docker2 preview, and matched browser checks. Final verification covers entity, reporting profile, year, month, type, search, category, tag, selection, drill-down, rollup, back, forward, layout movement, totals, the shared filtered set, console errors, and failed network requests.
