# Transaction Explorer Grid Editing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the Transaction Explorer ledger into a resizable, keyboard-navigable classification grid with immediate WDG/JPW edits, immutable audit history, recent changes, and safe reverts.

**Architecture:** `Myfin::ClassificationEditor` is the single deep write module for manual Explorer edits and reverts. `Myfin::ClassificationHistory` is the scoped read module for row and recent history. A Transaction Explorer Stimulus grid controller owns active-cell behavior while pure JavaScript helpers own deterministic movement and width calculations; Rails remains authoritative and returns one Turbo Stream response from one rebuilt report.

**Tech Stack:** Ruby 3.4.9, Rails 8.1, PostgreSQL 16, Minitest, Turbo Streams, Stimulus, semantic HTML tables, Tailwind design tokens, DS components, Node's built-in test runner.

**Spec:** `docs/superpowers/specs/2026-08-24-transaction-explorer-inline-classification-design.md`

## Global Constraints

- WDG and JPW remain independently editable; changing one never changes the other implicitly.
- Only manual Transaction Explorer edits and reverts enter this audit ledger. Importers and automated classification paths remain unchanged.
- Every write is account-scoped, requires annotate permission, checks an expected current category, appends history, and commits atomically.
- WDG edits and WDG reverts mirror Sure's native transaction category in the same database transaction.
- Blur, scrolling, and closing an uncommitted editor never save financial data.
- Audit events are append-only. A revert appends another event and never removes history.
- The isolated port-8950 preview is the only data-mutation target. No production deployment or production financial-data mutation is authorized.
- Before preview schema or image changes, run the documented preview backup and restore verification against the dedicated preview PostgreSQL container.
- Preserve the uncommitted category-panel persistence changes already present in `_filters.html.erb` and its controller test.

---

### Task 1: Append-only classification audit ledger

**Files:**
- Create: `db/migrate/20260824090000_create_myfin_classification_changes.rb`
- Create: `app/models/myfin/classification_change.rb`
- Modify: `app/models/myfin/transaction_classification.rb`
- Modify: `app/models/myfin/category_scheme.rb`
- Modify: `app/models/myfin/scheme_category.rb`
- Modify: `app/models/user.rb`
- Test: `test/models/myfin/classification_change_test.rb`

**Interfaces:**
- Produces: `Myfin::ClassificationChange` with `ACTIONS = %w[edit revert]`, `SOURCES = %w[transaction_explorer]`, nullable previous/new category pairs for `Uncategorized`, and immutable persisted rows.
- Consumes: existing MyFIN family, transaction, scheme, scheme-category, and user records.

- [ ] **Step 1: Write the failing model tests**

```ruby
test "records an edit with immutable category snapshots" do
  change = build_change(previous: @old_category, new: @new_category)
  assert change.save
  assert_equal @old_category.name, change.previous_category_name
  assert_equal @new_category.name, change.new_category_name
  assert_not change.update(action: "revert")
  assert_not change.destroy
end

test "represents uncategorized with a nil id and name pair" do
  change = build_change(previous: @old_category, new: nil)
  assert change.valid?
  change.new_category_name = "orphaned label"
  assert_not change.valid?
end
```

- [ ] **Step 2: Run the tests and confirm the audit model is missing**

Run: `bin/rails test test/models/myfin/classification_change_test.rb`

Expected: ERROR naming the missing `Myfin::ClassificationChange` constant or table.

- [ ] **Step 3: Add the migration and model**

Create UUID foreign keys for family, transaction, category scheme, actor, previous category, new category, and optional reverted change. Add snapshot-name strings, action, source, and timestamps. Use `on_delete: :nullify` for actor/category/reverted references, `on_delete: :cascade` for family/transaction, and indexes on `[family_id, created_at]`, `[transaction_id, category_scheme_id, created_at]`, and `reverted_change_id`.

The model validates paired ID/name presence and blocks update/destroy callbacks:

```ruby
validate :previous_snapshot_is_consistent
validate :new_snapshot_is_consistent
before_update :reject_mutation
before_destroy :reject_mutation

def reject_mutation
  errors.add(:base, "classification changes are append-only")
  throw :abort
end
```

- [ ] **Step 4: Run the model tests and migration check**

Run: `bin/rails db:migrate && bin/rails test test/models/myfin/classification_change_test.rb`

Expected: PASS with zero failures and the schema containing all declared foreign keys and indexes.

- [ ] **Step 5: Commit the audit foundation**

```bash
git add db/migrate/20260824090000_create_myfin_classification_changes.rb db/schema.rb app/models/myfin/classification_change.rb app/models/myfin/transaction_classification.rb app/models/myfin/category_scheme.rb app/models/myfin/scheme_category.rb app/models/user.rb test/models/myfin/classification_change_test.rb
git commit -m "Add classification change audit ledger"
```

### Task 2: Deep classification edit and revert module

**Files:**
- Create: `app/services/myfin/classification_editor.rb`
- Test: `test/services/myfin/classification_editor_test.rb`

**Interfaces:**
- Consumes: `entry: Entry`, `scheme: Myfin::CategoryScheme`, `target_category: Myfin::SchemeCategory | nil`, `expected_category: Myfin::SchemeCategory | nil`, `actor: User`, `source: "transaction_explorer"`, `revert_of: Myfin::ClassificationChange | nil`.
- Produces: `Myfin::ClassificationEditor::Result = Data.define(:classification, :change)`.
- Raises: `StaleClassification`, `InvalidCategory`, `InvalidRevert`, or `ActiveRecord::RecordInvalid` without partial writes.

- [ ] **Step 1: Write failing service tests for edit, uncategorize, and independent schemes**

```ruby
result = Myfin::ClassificationEditor.call(
  entry: @entry,
  scheme: @jpw_scheme,
  target_category: @new_jpw,
  expected_category: @old_jpw,
  actor: @user,
  source: "transaction_explorer"
)

assert_equal @new_jpw, result.classification.reload.scheme_category
assert_equal [@old_jpw.name, @new_jpw.name], [result.change.previous_category_name, result.change.new_category_name]
assert_equal @wdg_category, classification_for(@wdg_scheme).scheme_category
```

Also test a nil target destroys the current classification while recording `Uncategorized` and leaves the other scheme intact.

- [ ] **Step 2: Run the focused service tests and confirm the missing module failure**

Run: `bin/rails test test/services/myfin/classification_editor_test.rb`

Expected: ERROR naming the missing `Myfin::ClassificationEditor` constant.

- [ ] **Step 3: Implement the atomic edit path**

Inside one `Myfin::TransactionClassification.transaction`, lock the transaction, load the current scheme classification, compare its category ID with `expected_category&.id`, validate family/scheme membership, create the change snapshot, and update or destroy the current classification. For WDG, find or create the native family category by the selected name and assign it to the Sure transaction; a nil WDG target assigns a nil native category.

The module itself enforces annotate permission before entering the transaction:

```ruby
permission = entry.account.permission_for(actor)
raise NotAuthorized unless permission.in?([:owner, :full_control, :read_write])
```

- [ ] **Step 4: Add stale, invalid-family, permission-ready, and rollback tests**

Tests must prove a read-only actor, stale expected value, and cross-family category write no audit or classification changes. Stub the WDG native mirror to raise and assert both classification and audit counts remain unchanged.

- [ ] **Step 5: Implement revert through the same interface**

A revert requires `revert_of` to be the latest audit event for the same transaction and scheme. Its target is `revert_of.previous_category`; its expected category is the current category; its new audit row uses action `revert` and points to `revert_of`.

- [ ] **Step 6: Run all service tests**

Run: `bin/rails test test/services/myfin/classification_editor_test.rb`

Expected: PASS with edit, uncategorize, WDG mirror, stale write, invalid family, revert, superseded revert, and rollback cases green.

- [ ] **Step 7: Commit the mutation module**

```bash
git add app/services/myfin/classification_editor.rb test/services/myfin/classification_editor_test.rb
git commit -m "Add auditable classification editor"
```

### Task 3: Scoped classification history reads and routes

**Files:**
- Create: `app/queries/myfin/classification_history.rb`
- Create: `app/controllers/myfin/classification_changes_controller.rb`
- Create: `app/views/myfin/classification_changes/index.html.erb`
- Create: `app/views/myfin/classification_changes/show.html.erb`
- Create: `app/views/myfin/classification_changes/_event.html.erb`
- Modify: `config/routes.rb`
- Modify: `config/locales/views/myfin/en.yml`
- Test: `test/queries/myfin/classification_history_test.rb`
- Test: `test/controllers/myfin/classification_changes_controller_test.rb`

**Interfaces:**
- Produces: `Myfin::ClassificationHistory.for_entry(user:, entry:)` and `.recent(user:, cursor: nil, limit: 50)` returning accessible newest-first events without N+1 actor/category lookups.
- Produces routes for row history, recent history, and revert, all scoped by accessible entry or change.
- Consumes: `Myfin::ClassificationEditor` for revert writes and `DS::Dialog` with `variant: :drawer` for history presentation.

- [ ] **Step 1: Write failing query tests for access scope, ordering, and pagination**

Create changes on an owned account and an inaccessible account. Assert row and recent history include only the owned events, newest first, and cap results at the requested limit.

- [ ] **Step 2: Implement the history query**

Start from `Myfin::ClassificationChange.where(family: user.family)` and join through transaction entry/account access using the same accessible-account scope as the Explorer. Preload actor, scheme, previous category, new category, and reverted change. Use `(created_at, id)` as the stable cursor pair.

- [ ] **Step 3: Write failing controller tests**

Assert:

```ruby
get myfin_entry_classification_changes_path(@entry)
assert_response :success
assert_select "turbo-frame#drawer"

post revert_myfin_classification_change_path(@change), as: :turbo_stream
assert_response :success
assert_equal "revert", Myfin::ClassificationChange.order(:created_at).last.action
```

Also assert inaccessible history returns not found and read-only account users receive forbidden on revert.

- [ ] **Step 4: Add routes, controllers, drawers, and translations**

Use `DS::Dialog.new(variant: :drawer)` for both per-row history and Recent Changes. The event partial shows scheme, snapshot labels with `Uncategorized`, actor or `Deleted user`, timestamp, action, and revert target status.

Add exact route shapes:

```ruby
namespace :myfin do
  resources :entries, only: [] do
    resources :classification_changes, only: :index
  end

  resources :classification_changes, only: :index do
    post :revert, on: :member
  end
end
```

- [ ] **Step 5: Run history tests**

Run: `bin/rails test test/queries/myfin/classification_history_test.rb test/controllers/myfin/classification_changes_controller_test.rb`

Expected: PASS with access, pagination, rendering, permission, and revert tests green.

- [ ] **Step 6: Commit history reads and routes**

```bash
git add app/queries/myfin/classification_history.rb app/controllers/myfin/classification_changes_controller.rb app/views/myfin/classification_changes config/routes.rb config/locales/views/myfin/en.yml test/queries/myfin/classification_history_test.rb test/controllers/myfin/classification_changes_controller_test.rb
git commit -m "Add classification history and revert routes"
```

### Task 4: Explorer report metadata and edit endpoint

**Files:**
- Modify: `app/queries/myfin/transaction_explorer/report.rb`
- Modify: `app/controllers/myfin/transaction_explorers_controller.rb`
- Create: `app/controllers/myfin/transaction_explorer_classifications_controller.rb`
- Create: `app/views/myfin/transaction_explorer_classifications/update.turbo_stream.erb`
- Modify: `config/routes.rb`
- Test: `test/queries/myfin/transaction_explorer/report_test.rb`
- Test: `test/controllers/myfin/transaction_explorer_classifications_controller_test.rb`

**Interfaces:**
- Extends `Report::Row` with `transaction_id`, `wdg_category_id`, `jpw_category_id`, and `editable`.
- Extends `Report::Result` with active category options keyed by scheme name.
- Produces a Turbo-only update endpoint accepting `scheme_id`, `category_id`, `expected_category_id`, and the current Explorer filter query.
- Consumes: `Myfin::ClassificationEditor` and one rebuilt `Myfin::TransactionExplorer::Report`.

- [ ] **Step 1: Write failing report tests for editor metadata**

Assert each row exposes the exact current category IDs, transaction ID, and annotate capability derived from `entry.account.permission_for(user)`. Assert editor options contain every active family category even when current filters exclude all rows using it.

- [ ] **Step 2: Implement report metadata without per-row queries**

Build category option arrays once from the WDG and JPW schemes. Use already preloaded classifications for IDs and the preloaded account for `permission_for`. Keep the 250-row rendering cap in the controller only.

- [ ] **Step 3: Write failing update-controller tests**

Cover success, nil `category_id` for Uncategorized, forbidden annotate permission, stale expected value returning HTTP 409, invalid scheme/category returning 422, and a category edit that moves the row outside the active filter.

- [ ] **Step 4: Implement the update adapter and one-report Turbo response**

Resolve the entry through `Current.accessible_entries.transactions.find_by!(id: params[:entry_id])`, call `require_account_permission!(entry.account, :annotate)`, resolve family scheme/category, call the editor, rebuild the report once from permitted filter parameters, and render streams for shared set, metrics, rollup, ledger, filter form, notification tray, and an edit-result payload carrying entry ID, scheme, and focus fallback.

The entry-scoped route is:

```ruby
resources :entries, only: [] do
  resource :transaction_explorer_classification, only: :update
end
```

- [ ] **Step 5: Run report and controller tests**

Run: `bin/rails test test/queries/myfin/transaction_explorer/report_test.rb test/controllers/myfin/transaction_explorer_classifications_controller_test.rb`

Expected: PASS with zero N+1 regressions in the existing report query-count assertion.

- [ ] **Step 6: Commit report metadata and edit endpoint**

```bash
git add app/queries/myfin/transaction_explorer/report.rb app/controllers/myfin/transaction_explorers_controller.rb app/controllers/myfin/transaction_explorer_classifications_controller.rb app/views/myfin/transaction_explorer_classifications/update.turbo_stream.erb config/routes.rb test/queries/myfin/transaction_explorer/report_test.rb test/controllers/myfin/transaction_explorer_classifications_controller_test.rb
git commit -m "Add Transaction Explorer classification endpoint"
```

### Task 5: Pure spreadsheet navigation and column-width modules

**Files:**
- Create: `app/javascript/utils/transaction_explorer_grid_state.mjs`
- Create: `app/javascript/utils/transaction_explorer_column_widths.mjs`
- Test: `test/javascript/utils/transaction_explorer_grid_state_test.mjs`
- Test: `test/javascript/utils/transaction_explorer_column_widths_test.mjs`

**Interfaces:**
- Produces: `nextEditableCell({ cells, active, key, shiftKey })`, `focusFallback({ cells, previous })`, and `shouldOpenEditor({ key, printable })`.
- Produces: `clampWidth(column, width)`, `resizeWidths(current, column, delta)`, `resetWidth(column)`, `parseStoredWidths(json)`, and versioned storage key `transaction-explorer:column-widths:v1`.

- [ ] **Step 1: Write failing Node tests for grid movement**

Use literal cell fixtures such as `[{ entryId: "a", scheme: "WDG" }, { entryId: "a", scheme: "JPW" }, ...]`. Cover arrows, Tab, Shift+Tab, first/last rows, Enter/F2/printable keys, and fallback when the prior row disappears.

- [ ] **Step 2: Implement the minimal pure grid-state functions**

The functions return cell identities and never touch the DOM, submit forms, or mutate storage.

```javascript
export function nextEditableCell({ cells, active, key, shiftKey = false }) {
  const index = cells.findIndex(
    (cell) => cell.entryId === active.entryId && cell.scheme === active.scheme,
  );
  if (index === -1 || cells.length === 0) return null;
  const delta =
    key === "ArrowUp"
      ? -2
      : key === "ArrowDown"
        ? 2
        : key === "ArrowLeft" || (key === "Tab" && shiftKey)
          ? -1
          : 1;
  return cells[Math.max(0, Math.min(cells.length - 1, index + delta))];
}
```

- [ ] **Step 3: Write failing Node tests for widths**

Use a literal column definition map with default and minimum widths. Assert clamping, reset, malformed storage rejection, unknown-column rejection, and independent width updates.

- [ ] **Step 4: Implement the pure width functions**

Return new objects rather than mutating inputs. Keep desktop sticky-column offsets derivable from Date and Entity widths.

- [ ] **Step 5: Run JavaScript tests and formatting**

Run:

```bash
node --test test/javascript/utils/transaction_explorer_grid_state_test.mjs test/javascript/utils/transaction_explorer_column_widths_test.mjs
npm run format:check -- app/javascript/utils/transaction_explorer_grid_state.mjs app/javascript/utils/transaction_explorer_column_widths.mjs test/javascript/utils/transaction_explorer_grid_state_test.mjs test/javascript/utils/transaction_explorer_column_widths_test.mjs
```

Expected: all Node tests pass and Biome reports no formatting differences.

- [ ] **Step 6: Commit pure grid mechanics**

```bash
git add app/javascript/utils/transaction_explorer_grid_state.mjs app/javascript/utils/transaction_explorer_column_widths.mjs test/javascript/utils/transaction_explorer_grid_state_test.mjs test/javascript/utils/transaction_explorer_column_widths_test.mjs
git commit -m "Add Transaction Explorer grid mechanics"
```

### Task 6: Resizable semantic grid and inline category editors

**Files:**
- Create: `app/javascript/controllers/transaction_explorer_grid_controller.js`
- Create: `app/javascript/controllers/transaction_explorer_columns_controller.js`
- Create: `app/views/myfin/transaction_explorers/_category_cell.html.erb`
- Modify: `app/views/myfin/transaction_explorers/_ledger.html.erb`
- Modify: `app/views/myfin/transaction_explorers/show.html.erb`
- Modify: `config/locales/views/myfin/en.yml`
- Test: `test/controllers/myfin/transaction_explorer_controller_test.rb`

**Interfaces:**
- Consumes the pure Task 5 modules and report metadata from Task 4.
- Produces DOM targets keyed by `data-entry-id` and `data-scheme`, roving tabindex, edit-mode controls, searchable native selects or the existing DS-compatible combobox, a `colgroup`, resize handles, reset control, and Turbo lifecycle hooks.

- [ ] **Step 1: Write failing rendering tests**

Assert the default ledger remains a semantic table, the header contains `Edit categories`, `Recent changes`, and `Reset column widths`, each header has one keyboard-focusable resize handle, only WDG/JPW cells have editor metadata, and read-only rows do not render an editor form.

- [ ] **Step 2: Add the colgroup and resize controller**

Render one `<col>` per declared column. Pointer drag updates the matching col width; arrow keys change fixed increments; double-click resets one column; reset control clears the versioned storage key. Date and Entity receive desktop sticky offsets calculated from the current widths.

```erb
<colgroup data-transaction-explorer-columns-target="colgroup">
  <% transaction_explorer_columns.each do |column| %>
    <col data-column="<%= column.key %>" style="width: <%= column.default_width %>px">
  <% end %>
</colgroup>
```

- [ ] **Step 3: Add edit mode and category-cell partial**

The partial renders a read label and a hidden editor form containing scheme, target category, expected category, and the current query string. `Uncategorized` uses a blank category value. Use functional design tokens and existing DS primitives; do not add raw palette classes or a custom dialog/select shape.

- [ ] **Step 4: Add active-cell keyboard behavior**

Implement roving tabindex and Task 5 movement. Enter, F2, double-click, or printable input opens; Escape cancels; Enter or a deliberate option selection submits; blur only cancels an uncommitted editor. Ignore navigation keys from nested editor controls.

- [ ] **Step 5: Preserve state through Turbo replacements**

Before render, record scroll position, edit mode, active cell, and open editor identity. After render, restore widths, scroll, and logical focus. If the row disappeared, use `focusFallback` and announce that the row moved out of the current filter.

- [ ] **Step 6: Run rendering, JavaScript, and style checks**

Run:

```bash
bin/rails test test/controllers/myfin/transaction_explorer_controller_test.rb test/controllers/myfin/transaction_explorer_classifications_controller_test.rb
node --test test/javascript/utils/transaction_explorer_grid_state_test.mjs test/javascript/utils/transaction_explorer_column_widths_test.mjs
npm run lint
```

Expected: all focused tests pass and Biome reports no lint errors.

- [ ] **Step 7: Commit the grid UI**

```bash
git add app/javascript/controllers/transaction_explorer_grid_controller.js app/javascript/controllers/transaction_explorer_columns_controller.js app/views/myfin/transaction_explorers/_category_cell.html.erb app/views/myfin/transaction_explorers/_ledger.html.erb app/views/myfin/transaction_explorers/show.html.erb config/locales/views/myfin/en.yml test/controllers/myfin/transaction_explorer_controller_test.rb
git commit -m "Build editable Transaction Explorer grid"
```

### Task 7: Row history, Recent Changes, and queued undo

**Files:**
- Create: `app/views/myfin/transaction_explorers/_edit_result.html.erb`
- Modify: `app/views/myfin/transaction_explorers/_ledger.html.erb`
- Modify: `app/views/myfin/transaction_explorers/show.html.erb`
- Modify: `app/views/myfin/classification_changes/index.html.erb`
- Modify: `app/views/myfin/classification_changes/show.html.erb`
- Modify: `app/javascript/controllers/transaction_explorer_grid_controller.js`
- Test: `test/controllers/myfin/transaction_explorer_controller_test.rb`
- Test: `test/controllers/myfin/classification_changes_controller_test.rb`

**Interfaces:**
- Consumes: history routes from Task 3 and update/revert results from Tasks 2 and 4.
- Produces: per-row history links targeting the `drawer` Turbo frame, header Recent Changes drawer, and queued undo notices referencing immutable change IDs.

- [ ] **Step 1: Write failing UI integration tests**

Assert each editable row links to its scoped history, Recent Changes targets the drawer, a successful edit renders an undo action for its change ID, and a successful revert renders a new revert event rather than deleting the original.

- [ ] **Step 2: Render row and global history controls using DS primitives**

Use `DS::Button` for header actions and `DS::Dialog` drawer views. Keep history actions unavailable on inaccessible rows. Show a bounded 50-event page and a cursor-based More link.

- [ ] **Step 3: Queue undo notices in the grid controller**

Each successful edit result appends a notice keyed by change ID. Expiry removes only the notice; it never changes data. Clicking Undo submits the revert route and disables that notice until the server responds. A 409 replaces the notice with the server-current value and a link to history.

- [ ] **Step 4: Run UI integration tests**

Run: `bin/rails test test/controllers/myfin/transaction_explorer_controller_test.rb test/controllers/myfin/transaction_explorer_classifications_controller_test.rb test/controllers/myfin/classification_changes_controller_test.rb`

Expected: PASS with edit, history, recent changes, undo, conflict, and drawer rendering assertions green.

- [ ] **Step 5: Commit history and undo UI**

```bash
git add app/views/myfin/transaction_explorers app/views/myfin/classification_changes app/javascript/controllers/transaction_explorer_grid_controller.js test/controllers/myfin/transaction_explorer_controller_test.rb test/controllers/myfin/classification_changes_controller_test.rb
git commit -m "Add classification history and undo UI"
```

### Task 8: Affected-suite, performance, and isolated preview verification

**Files:**
- Modify only if measurement proves necessary: `app/queries/myfin/transaction_explorer/report.rb`
- Record implementation notes in: `docs/superpowers/plans/2026-08-24-transaction-explorer-grid-editing.md`

**Interfaces:**
- Consumes every preceding task.
- Produces passing affected checks, measured edit latency, a restore-tested preview backup fingerprint, an isolated preview image/database migration, and rendered edit/revert proof.

- [ ] **Step 1: Run the affected automated suite**

Run:

```bash
bin/rails test test/models/myfin test/services/myfin test/queries/myfin test/controllers/myfin
node --test test/javascript/utils/*.mjs
bin/rubocop app/models/myfin app/services/myfin app/queries/myfin app/controllers/myfin test/models/myfin test/services/myfin test/queries/myfin test/controllers/myfin
npm run lint
bin/brakeman -q
```

Expected: zero test failures, RuboCop offenses, Biome errors, or new Brakeman warnings in the changed surface.

- [ ] **Step 2: Measure one report rebuild before preview deployment**

Against a restored copy with approximately 2,108 Explorer rows, measure the update request from submit through Turbo response. Record median of five edits and whether scroll/focus restoration is perceptibly stable. If the response is too slow for continuous editing, optimize inside `Report` and rerun the same controller/report tests; do not split totals and rollup into separate controller queries.

- [ ] **Step 3: Create and restore-test the dedicated preview backup**

Use the MyFIN preview adapter's preparation command against the current dedicated port-8950 database, record the exact fingerprint and aggregate counts, and verify restore before applying the migration. Do not use the production database or production backup as the schema-change rollback for this task.

- [ ] **Step 4: Build and deploy a traceable preview image**

Build from the exact branch commit, tag the image with that commit plus `grid-editing`, migrate only the dedicated preview PostgreSQL container, keep the prior preview image/database backup as rollback, and verify dedicated Redis still has exactly one consumer and no worker.

- [ ] **Step 5: Verify the rendered spreadsheet workflow with one safe sample transaction**

In the in-app browser on port `8950`:

1. confirm 2,108 baseline rows or document the fresh count
2. resize Date, Entity, WDG, JPW, Description, Account, and Amount; reload and confirm persistence
3. enter edit mode and navigate WDG/JPW cells with mouse, arrows, Tab, Shift+Tab, Enter, F2, and Escape
4. change one safe sample JPW category and confirm cell, rollup, totals, and filters update
5. open row history and Recent Changes and confirm the exact audit event
6. undo the edit and confirm a revert event restores the original category
7. confirm the original event remains in history
8. verify production port `8943` still runs image `sure-myfin:8ce2c8fa56b6` and returns HTTP 200

- [ ] **Step 6: Commit any measured performance correction and update the plan evidence**

If no performance code changed, update only the plan's execution notes with commands, counts, latency, preview image, backup fingerprint, rollback identity, and browser result. Commit that evidence separately from product code.

```bash
git add docs/superpowers/plans/2026-08-24-transaction-explorer-grid-editing.md app/queries/myfin/transaction_explorer/report.rb
git commit -m "Verify Transaction Explorer grid editing"
```

## Recommended execution routing

- Keep the parent task on the current high-reasoning model for architecture, checkpoint review, financial semantics, preview authorization, and final verification.
- Use one sequential `worker` on `gpt-5.6-terra` with high reasoning for Tasks 1 through 4. These tasks own the schema, atomic mutation contract, permissions, and audit correctness.
- Use one `spark-coder` for Task 5 after Task 4 is accepted; its scope is limited to the four pure JavaScript files.
- Return Tasks 6 and 7 to `gpt-5.6-terra` high or the parent task because they integrate Rails, Turbo, accessibility, focus restoration, and financial write feedback.
- Use a separate `spark-tester` only for the affected automated commands. The parent task reads the actual output and performs Task 8's database and browser verification directly.
- Never run two editing workers against the same files concurrently. Each task begins only after the preceding task's diff and focused tests pass review.
