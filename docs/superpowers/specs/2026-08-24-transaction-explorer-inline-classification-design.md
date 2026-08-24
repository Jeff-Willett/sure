# Transaction Explorer inline classification design

## Status

Approved in conversation by Jeff Willett on 2026-08-24. Implementation requires review of this written spec. This design does not authorize a production deployment or changes to production financial data.

## Goal

Make the Transaction Explorer ledger a practical classification workspace. Users can resize every column, enter an explicit edit mode, change WDG or JPW without leaving the page, inspect permanent history per transaction and across the table, and restore an older value without deleting audit evidence.

## Non-goals

- No automatic JPW-to-WDG assignment in this version.
- No GCI, Donna, or Danielle category-scheme migration.
- No bulk edit, rule creation, or spreadsheet synchronization.
- No editing of entity, date, description, account, amount, or transaction type.
- No production data apply or production deployment.

## Classification contract

WDG and JPW remain independently editable. A future feature may suggest a WDG parent after the known category conflicts and entity-specific schemes are resolved, but this version never changes the other scheme implicitly.

Each edit and revert runs through one service. The service must:

1. scope the entry through the current user's accessible transaction entries
2. require annotate permission on the account
3. lock the transaction and current classification
4. reject a stale expected category instead of overwriting a concurrent edit
5. append an audit record
6. update the current classification
7. mirror a WDG change to Sure's native transaction category
8. commit all writes together or roll back all of them

## Audit ledger

Add `myfin_classification_changes` as an append-only table. Each row stores:

- family, transaction, category scheme, and actor IDs
- previous and new scheme-category IDs
- previous and new category names as immutable snapshots
- action type: `edit` or `revert`
- source surface: `transaction_explorer`
- optional `reverted_change_id`
- creation timestamp

Foreign keys to category and user records may become null if those records are later removed. Snapshot names remain required so history stays understandable.

Application code does not update or destroy audit rows. A revert creates a new change row whose new value is the selected historical value and whose `reverted_change_id` points to the change being restored. The current classification remains the fast read model used by reports.

## Routes and service interface

The Explorer uses dedicated member routes scoped by entry ID:

- update one scheme classification
- list one transaction's classification history
- list recent accessible classification changes
- revert one accessible change

The write service accepts the entry, scheme, target category, expected current category, actor, and action metadata. Controllers do not duplicate permission, locking, audit, mirroring, or stale-write logic.

## Edit mode

The Transactions header has an `Edit categories` toggle. Edit mode is local UI state and defaults off after a new browser session. Only users who can annotate the visible accounts see the control.

When active:

- WDG and JPW cells render compact searchable category dropdowns.
- All other cells remain read-only.
- Selecting a category submits immediately.
- The active cell shows a saving state and prevents a second submission.
- Success replaces the affected Explorer state and shows an Undo toast.
- Validation, permission, or stale-write errors stay beside the cell and preserve the user's current table position.

The server response recalculates the report from the current URL filters. Ledger, metrics, rollup, shared-set counts, and category filter options therefore continue to derive from the same filtered row set. If the edited row no longer matches an active category filter, it leaves the ledger after save and the toast explains that the row moved out of the current view.

## History and undo

Edit mode adds a history action to each row. It opens an inline drawer for that transaction with newest-first WDG and JPW changes. Each event shows scheme, old value, new value, actor, time, and whether it was a revert.

The Transactions header also has `Recent changes`. It opens a table-wide panel scoped to changes the current user may access. The panel shows the same fields plus transaction date and safe description context. It uses bounded pagination rather than loading the entire history.

The immediate Undo toast calls the same revert route used by permanent history. Undo is allowed only while the referenced change remains the latest change for that transaction and scheme. If another edit has occurred, the server returns a conflict and the UI refreshes the current value.

## Resizable columns

Every ledger header has a drag handle. A dedicated Stimulus controller manages a `colgroup` so header and body widths stay aligned.

- Date, entity, WDG, JPW, description, account, and amount each have minimum widths.
- Description receives remaining width when the table is wider than the saved columns.
- Horizontal scrolling remains available when saved widths exceed the viewport.
- Widths persist in `localStorage` under a versioned Transaction Explorer key.
- Double-clicking a handle resets that column to its default.
- Keyboard users can focus a handle and adjust it in fixed increments with arrow keys.
- Resizing is presentation-only and never submits the filter form.

## Permissions and privacy

- Read history only for entries reachable through `Current.accessible_entries.transactions`.
- Require annotate permission for edit and revert.
- Validate that schemes and categories belong to `Current.family`.
- Do not expose account credentials, provider payloads, transaction lineage payloads, or inaccessible actors.
- Display a neutral deleted-user label if a historical actor no longer exists.

## Error handling

- Invalid scheme or category returns an inline validation error.
- A stale expected category returns HTTP 409 with the server's current label.
- A reverted or non-latest change returns HTTP 409 and does not write another event.
- A missing or inaccessible entry returns the normal not-found response.
- A failed native WDG mirror rolls back both the classification and audit record.
- A Turbo failure leaves the current cell value visible and offers retry; it never claims the save succeeded.

## Performance

The ledger still renders at most 250 rows. Category option collections load once per request and are reused by cell editors. Recent history uses an index beginning with family and creation time; row history uses transaction, scheme, and creation time. Turbo responses may refresh the Explorer's report sections but must not issue one category query per row.

## Verification

Automated checks must prove:

- an authorized edit changes one scheme and appends one correct audit row
- JPW edits do not change WDG, and WDG edits do not change JPW
- WDG edits mirror Sure's native category in the same transaction
- permission failures, invalid cross-family categories, and stale expected values write nothing
- edit and audit writes roll back together on failure
- an immediate undo restores the prior value and appends a revert event
- an older or superseded event cannot be reverted as though it were current
- row history and recent history exclude inaccessible transactions
- report totals, rollup, ledger, and filter options refresh from the same post-edit set
- a row leaves a filtered view when its edited category no longer matches
- the resize controller persists, restores, resets, clamps, and keyboard-adjusts widths
- edit mode does not make non-category cells editable

Browser verification on the isolated port-8950 preview must show representative sample edits and reverts. Before schema or image changes to the production-data preview clone, run the documented preview backup and restore verification. Verification may mutate only the isolated preview clone and must record the exact sample transaction and before-and-after category values without exposing private transaction details in chat or screenshots.

## Rollout and rollback

Implementation stays on `codex/myfin-post-foundation` and deploys only to the isolated port-8950 preview. The preview keeps its dedicated PostgreSQL and Redis containers. No production deployment is included.

Rollback restores the preview database backup and returns the preview container to the prior image. Because audit history is part of the schema, rollback verification must prove both current classifications and audit rows match the pre-deploy snapshot.
