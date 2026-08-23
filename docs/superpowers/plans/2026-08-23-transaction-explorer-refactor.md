# Transaction Explorer Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor Transaction Explorer into one deep reporting module that loads accessible entries once and returns rows, metrics, hierarchical rollup, filter options, and selected filter state without changing the working frame.

**Architecture:** `Myfin::TransactionExplorer::Filters` owns request normalization and all, none, or selected state. `Myfin::TransactionExplorer::Report` is the single reporting seam; it owns the accessible dataset, allocation-aware rows, filtering, metrics, hierarchy, and options. The Rails controller becomes a thin adapter and the ERB page becomes a composition of focused rendering partials.

**Tech Stack:** Ruby 3.4, Rails 8.1, PostgreSQL 16, ERB, Hotwire and Stimulus, Minitest, Node test runner, RuboCop, erb_lint, Biome

**Spec:** `docs/superpowers/specs/2026-08-23-transaction-explorer-refactor-design.md`

## Global Constraints

- Preserve the current visual design and all slicer behavior.
- Preserve the 20-row combined and 12-row Personal-only sample checkpoints.
- Metrics, rollup, and ledger must derive from the same final row array.
- Load the accessible entry relation once per report construction.
- Preserve allocation-aware amounts for partial entity ownership.
- Keep the no-selection sentinel private to `Filters`.
- Keep preview sign-in test-only and flag-gated.
- Do not deploy to the production Sure container.
- Do not mutate live MyFIN financial data.
- Use `codex/transaction-explorer-frame` and the isolated `sure_frame_preview` database.
- Run focused tests before broader quality gates.

---

### Task 1: Encapsulate filter normalization

**Files:**
- Create: `app/queries/myfin/transaction_explorer/filters.rb`
- Create: `test/queries/myfin/transaction_explorer/filters_test.rb`
- Test: `test/queries/myfin/transaction_explorer/filters_test.rb`

**Interfaces:**
- Consumes: Rails-style params responding to `to_h`
- Produces: `Myfin::TransactionExplorer::Filters.from_params(params)`, `#values_for(key)`, `#explicit?(key)`, `#selected_values(key, available:)`, and `#search`

- [ ] **Step 1: Write the failing filter tests**

```ruby
require "test_helper"

class MyfinTransactionExplorerFiltersTest < ActiveSupport::TestCase
  test "normalizes typed values and hides the no-selection sentinel" do
    filters = Myfin::TransactionExplorer::Filters.from_params(
      entity_ids: [ "entity-1", "__none__", "" ],
      years: [ "2025", "2026" ],
      months: [ "8" ],
      types: [ "Expense" ],
      search: "  rent  "
    )

    assert_equal [ "entity-1" ], filters.values_for(:entity_ids)
    assert_equal [ 2025, 2026 ], filters.values_for(:years)
    assert_equal [ 8 ], filters.values_for(:months)
    assert_equal [ "Expense" ], filters.values_for(:types)
    assert_equal "rent", filters.search
  end

  test "distinguishes absent filters from an explicit empty selection" do
    absent = Myfin::TransactionExplorer::Filters.from_params({})
    cleared = Myfin::TransactionExplorer::Filters.from_params(years: [ "__none__" ])

    assert_not absent.explicit?(:years)
    assert_equal [ "2025", "2026" ], absent.selected_values(:years, available: [ 2025, 2026 ])
    assert cleared.explicit?(:years)
    assert_empty cleared.values_for(:years)
    assert_empty cleared.selected_values(:years, available: [ 2025, 2026 ])
  end
end
```

- [ ] **Step 2: Run the tests and verify the missing module failure**

Run:

```bash
bin/rails test test/queries/myfin/transaction_explorer/filters_test.rb
```

Expected: failure or error because `Myfin::TransactionExplorer::Filters` does not exist.

- [ ] **Step 3: Implement the immutable Filters value object**

```ruby
module Myfin
  module TransactionExplorer
    class Filters
      NONE_VALUE = "__none__"
      FILTER_KEYS = %i[entity_ids years months types wdg_categories jpw_categories].freeze
      INTEGER_KEYS = %i[years months].freeze

      def self.from_params(params)
        new(params.to_h.with_indifferent_access)
      end

      attr_reader :search

      def initialize(params)
        @explicit = FILTER_KEYS.index_with { |key| params.key?(key) }
        @values = FILTER_KEYS.index_with { |key| normalize(key, params[key]) }
        @search = params[:search].to_s.strip.downcase
      end

      def values_for(key)
        @values.fetch(key.to_sym)
      end

      def explicit?(key)
        @explicit.fetch(key.to_sym)
      end

      def selected_values(key, available:)
        return available.map(&:to_s) unless explicit?(key)

        values_for(key).map(&:to_s)
      end

      private
        def normalize(key, raw)
          values = Array(raw).compact_blank.reject { |value| value == NONE_VALUE }
          return values.map(&:to_i).uniq if INTEGER_KEYS.include?(key)

          values.map(&:to_s).uniq
        end
    end
  end
end
```

- [ ] **Step 4: Run the focused tests**

Run the Task 1 test file. Expected: all tests pass.

- [ ] **Step 5: Commit the filter interface**

```bash
git add app/queries/myfin/transaction_explorer/filters.rb test/queries/myfin/transaction_explorer/filters_test.rb
git commit -m "Encapsulate Transaction Explorer filters"
```

---

### Task 2: Build the deep Report module and remove the duplicate dataset load

**Files:**
- Create: `app/queries/myfin/transaction_explorer/report.rb`
- Create: `test/queries/myfin/transaction_explorer/report_test.rb`
- Reference: `app/queries/myfin/transaction_explorer_query.rb`
- Reference: `test/queries/myfin/transaction_explorer_query_test.rb`

**Interfaces:**
- Consumes: `user:` and `Myfin::TransactionExplorer::Filters`
- Produces: `Myfin::TransactionExplorer::Report.call(user:, filters:) -> Result`
- `Result` provides `rows`, `metrics`, `rollup`, `filter_options`, and `selected_filters`

- [ ] **Step 1: Write a failing one-load and allocation test**

Add a report test using two entities and one partially allocated entry:

```ruby
filters = Myfin::TransactionExplorer::Filters.from_params(
  entity_ids: [ personal.id ], years: [ "2026" ], months: [ "8" ]
)

report = Myfin::TransactionExplorer::Report.call(user: user, filters: filters)

assert_equal [ personal_entry.id, shared_entry.id ], report.rows.map(&:entry_id)
assert_equal(-60.to_d, report.rows.find { |row| row.entry_id == shared_entry.id }.amount)
assert_equal 2, report.metrics.transactions
assert_equal report.rows.sum(&:amount), report.rollup.sum(&:amount)
```

Include `SqlQueryCapture` and use:

```ruby
queries = capture_sql_queries do
  Myfin::TransactionExplorer::Report.call(user: user, filters: filters)
end
entry_loads = queries.count { |sql| sql.include?('FROM "entries"') && sql.include?("entryable_type") }
assert_equal 1, entry_loads
```

Do not count association preload queries as duplicate entry loads.

- [ ] **Step 2: Run the report test and verify failure**

Expected: failure because the new Report module does not exist.

- [ ] **Step 3: Implement source rows and one entry load**

Define the result types in `Report`:

```ruby
Row = Data.define(:entry_id, :date, :description, :amount, :type, :entity_ids, :entity_names, :wdg, :jpw, :account_name)
Metrics = Data.define(:transactions, :expenses, :income, :transfer_net)
RollupCategory = Data.define(:jpw, :amount, :count)
RollupGroup = Data.define(:wdg, :amount, :categories)
RollupType = Data.define(:type, :amount, :groups)
FilterOptions = Data.define(:entities, :years, :months, :types, :wdg_categories, :jpw_categories)
Result = Data.define(:rows, :metrics, :rollup, :filter_options, :selected_filters)
```

Load entries once:

```ruby
def source_entries
  @source_entries ||= Entry
    .where(entryable_type: "Transaction")
    .where(account_id: user.accessible_accounts.select(:id))
    .joins(:myfin_allocations)
    .where(myfin_entry_allocations: { entity_id: all_entity_ids })
    .distinct
    .includes(:account, { myfin_allocations: :entity }, entryable: { myfin_classifications: [ :category_scheme, :scheme_category ] })
    .to_a
end
```

Build available rows and selected rows from the cached `source_entries`. Never invoke the relation twice.

- [ ] **Step 4: Apply Filters without leaking the sentinel**

For each filter key:

```ruby
def keep_filter?(key, value)
  return true unless filters.explicit?(key)

  filters.values_for(key).include?(value)
end
```

If a filter is explicit and `values_for` is empty, every row must be removed.

- [ ] **Step 5: Run the report tests**

Expected: the allocation, scoping, order, and one-load assertions pass.

- [ ] **Step 6: Commit the report row pipeline**

```bash
git add app/queries/myfin/transaction_explorer/report.rb test/queries/myfin/transaction_explorer/report_test.rb
git commit -m "Add Transaction Explorer report module"
```

---

### Task 3: Move metrics, hierarchy, options, and selected state into Report

**Files:**
- Modify: `app/queries/myfin/transaction_explorer/report.rb`
- Modify: `test/queries/myfin/transaction_explorer/report_test.rb`

**Interfaces:**
- Extends the Task 2 `Result` fields with fully populated render-ready data
- Produces `RollupType -> RollupGroup -> RollupCategory` hierarchy

- [ ] **Step 1: Write failing literal-output tests**

Add a fixture set with one Expense, one Income, and one Transfer. Assert:

```ruby
assert_equal 3, report.metrics.transactions
assert_equal 120.to_d, report.metrics.expenses
assert_equal 3000.to_d, report.metrics.income
assert_equal 500.to_d, report.metrics.transfer_net

assert_equal [ "Expense", "Income", "Transfer" ], report.rollup.map(&:type)
assert_equal "Shopping", report.rollup.first.groups.first.wdg
assert_equal "Groceries", report.rollup.first.groups.first.categories.first.jpw
```

Add an explicit empty Year filter and assert empty rows, zero metrics, and empty rollup while filter options still contain both available years.

Add a cross-family entity ID filter and assert zero rows. Add one entry without WDG or JPW classifications and assert its row exposes `Uncategorized` for both fields.

- [ ] **Step 2: Run tests and verify the new output assertions fail**

- [ ] **Step 3: Implement metrics from final rows**

```ruby
Metrics.new(
  transactions: rows.size,
  expenses: rows.select { |row| row.type == "Expense" }.sum(BigDecimal("0")) { |row| row.amount.abs },
  income: rows.select { |row| row.type == "Income" }.sum(BigDecimal("0"), &:amount),
  transfer_net: rows.select { |row| row.type == "Transfer" }.sum(BigDecimal("0"), &:amount)
)
```

- [ ] **Step 4: Implement hierarchical rollup from final rows**

Group only inside Report. Sort type using `TYPE_ORDER`, then WDG and JPW by absolute amount descending and name.

- [ ] **Step 5: Implement filter options from unfiltered available rows**

Return active entities with accessible allocations, sorted years and months, `TYPE_ORDER` types, and sorted WDG and JPW names.

- [ ] **Step 6: Implement selected filter strings through Filters**

```ruby
selected_filters = {
  entity_ids: filters.selected_values(:entity_ids, available: filter_options.entities.map(&:first)),
  years: filters.selected_values(:years, available: filter_options.years),
  months: filters.selected_values(:months, available: filter_options.months),
  types: filters.selected_values(:types, available: filter_options.types),
  wdg_categories: filters.selected_values(:wdg_categories, available: filter_options.wdg_categories),
  jpw_categories: filters.selected_values(:jpw_categories, available: filter_options.jpw_categories)
}
```

- [ ] **Step 7: Run report and existing explorer query tests**

Expected: new report tests pass. Existing query tests may still use the old module until Task 4.

- [ ] **Step 8: Commit the complete report result**

```bash
git add app/queries/myfin/transaction_explorer/report.rb test/queries/myfin/transaction_explorer/report_test.rb
git commit -m "Deepen Transaction Explorer report results"
```

---

### Task 4: Replace controller and view calculations with the Report interface

**Files:**
- Modify: `app/controllers/myfin/transaction_explorers_controller.rb`
- Modify: `app/views/myfin/transaction_explorers/show.html.erb`
- Create: `app/views/myfin/transaction_explorers/_filters.html.erb`
- Create: `app/views/myfin/transaction_explorers/_metrics.html.erb`
- Create: `app/views/myfin/transaction_explorers/_rollup.html.erb`
- Create: `app/views/myfin/transaction_explorers/_ledger.html.erb`
- Preserve: `app/views/myfin/transaction_explorers/_slicer.html.erb`
- Modify: `test/controllers/myfin/transaction_explorer_controller_test.rb`

**Interfaces:**
- Consumes: `Filters.from_params` and `Report.call`
- Produces: the unchanged Transaction Explorer HTML and the shared-set data attributes

- [ ] **Step 1: Keep the controller test as a green characterization of the rendered contract**

Keep the current row, slicer-toolbar, hidden-sentinel, nav, and hidden-profile assertions. Add literal metrics and rollup text assertions for the one-row request, then run the test against the current implementation and confirm it is green before refactoring.

- [ ] **Step 2: Run the controller characterization before changing implementation**

Expected: the existing implementation passes. This is a behavior-preserving refactor, so the same test must remain green after the controller and views switch to Report.

- [ ] **Step 3: Thin the controller**

The complete action should have this shape:

```ruby
def show
  filters = Myfin::TransactionExplorer::Filters.from_params(filter_params)
  @report = Myfin::TransactionExplorer::Report.call(user: Current.user, filters: filters)
  @visible_rows = @report.rows.first(MAX_VISIBLE_ROWS)
  @breadcrumbs = [
    [ t("breadcrumbs.home"), root_path ],
    [ t("myfin.transaction_explorer.title"), nil ]
  ]
end
```

Delete `selected_filters`, `selected_or_all`, and `metrics` from the controller.

- [ ] **Step 4: Extract rendering partials without changing classes or copy**

Use these locals:

```erb
<%= render "filters", report: @report %>
<%= render "metrics", metrics: @report.metrics %>
<%= render "rollup", rollup: @report.rollup %>
<%= render "ledger", rows: @visible_rows, total_count: @report.rows.size %>
```

The show template retains the screen-reader heading and shared-set proof strip only. Do not add a visible page header.

- [ ] **Step 5: Render hierarchy directly**

`_rollup.html.erb` iterates `rollup`, `type.groups`, and `group.categories`. It must not call `group_by` or `sum`.

- [ ] **Step 6: Run controller tests and ERB lint**

Run:

```bash
bin/rails test test/controllers/myfin/transaction_explorer_controller_test.rb
bundle exec erb_lint app/views/myfin/transaction_explorers app/views/layouts/application.html.erb
```

- [ ] **Step 7: Commit the thin Rails adapter and partials**

```bash
git add app/controllers/myfin/transaction_explorers_controller.rb app/views/myfin/transaction_explorers test/controllers/myfin/transaction_explorer_controller_test.rb
git commit -m "Render Transaction Explorer from report results"
```

---

### Task 5: Remove the old shallow query and preserve regression coverage

**Files:**
- Delete: `app/queries/myfin/transaction_explorer_query.rb`
- Delete after migrating its unique cases: `test/queries/myfin/transaction_explorer_query_test.rb`
- Modify: `test/queries/myfin/transaction_explorer/report_test.rb`
- Search: all application and test references to `TransactionExplorerQuery`

**Interfaces:**
- Removes the old `Myfin::TransactionExplorerQuery.call` interface
- Makes `Myfin::TransactionExplorer::Report.call` the only reporting seam

- [ ] **Step 1: Search for old-interface callers**

Run:

```bash
rg -n "TransactionExplorerQuery" app test
```

Expected before deletion: the old module definition and old test references only. The controller must already use `Myfin::TransactionExplorer::Report` from Task 4.

- [ ] **Step 2: Move unique old tests to Report tests**

Preserve literal assertions for:

- one filtered row set feeding rollup
- unselected filter options remaining available
- deterministic date ordering

- [ ] **Step 3: Delete the old query and old test file**

- [ ] **Step 4: Run all Transaction Explorer tests**

Run:

```bash
bin/rails test \
  test/queries/myfin/transaction_explorer/filters_test.rb \
  test/queries/myfin/transaction_explorer/report_test.rb \
  test/controllers/myfin/transaction_explorer_controller_test.rb \
  test/controllers/preview_sessions_controller_test.rb
node --test test/javascript/utils/slicer_selection_test.mjs
```

- [ ] **Step 5: Confirm no old-interface references remain and commit**

```bash
rg -n "TransactionExplorerQuery" app test
git add -A app/queries/myfin test/queries/myfin
git commit -m "Remove shallow Transaction Explorer query"
```

---

### Task 6: Quality gates and stable preview verification

**Files:**
- Verify only; no intended source changes
- Preview source: `/opt/docker/builds/sure-3326d07bc52e`
- Preview container: `myfin-transaction-explorer-frame`
- Preview database: `sure_frame_preview`

**Interfaces:**
- Consumes: completed branch source
- Produces: passing quality evidence and unchanged browser behavior

- [ ] **Step 1: Run Ruby, ERB, and JavaScript checks**

```bash
bin/rubocop \
  app/queries/myfin/transaction_explorer \
  app/controllers/myfin/transaction_explorers_controller.rb \
  test/queries/myfin/transaction_explorer \
  test/controllers/myfin/transaction_explorer_controller_test.rb

bundle exec erb_lint app/views/myfin/transaction_explorers app/views/layouts/application.html.erb

node node_modules/@biomejs/biome/bin/biome check \
  app/javascript/controllers/transaction_explorer_slicer_controller.js \
  app/javascript/utils/slicer_selection.mjs \
  test/javascript/utils/slicer_selection_test.mjs
```

- [ ] **Step 2: Sync only the branch source to the isolated preview build directory**

Do not copy `.env`, secrets, production database files, or volumes.

- [ ] **Step 3: Recompile preview assets and restart only the preview container**

Keep `POSTGRES_DB=sure_frame_preview` and port `8950`. Do not restart `myfin-sure-web-1`, `myfin-sure-worker-1`, PostgreSQL, or Redis.

- [ ] **Step 4: Verify the combined checkpoint in Chrome**

At `http://100.104.3.101:8950/myfin/transaction_explorer` verify:

- 20 filtered transactions
- Rollup: 20
- Ledger: 20
- visible select-all, clear-all, and mode icons on slicers

- [ ] **Step 5: Verify Personal-only checkpoint in Chrome**

Deselect Green Capital Investing and verify:

- 12 filtered transactions
- Rollup: 12
- Ledger: 12

Reset to all entities after verification.

- [ ] **Step 6: Measure report construction**

Use `Benchmark.realtime` around 10 report constructions against `sure_frame_preview`. Record median and maximum wall time. Do not optimize further unless median exceeds 250 ms or maximum exceeds 500 ms in the isolated container.

- [ ] **Step 7: Commit any verification-only fixes and push**

If no source fix is required, push the existing commits. Report branch, commit, preview URL, tests, lint, and benchmark results.
