# Transaction Explorer reporting-module refactor design

## Status

Approved for implementation by Jeff Willett on 2026-08-23. This refactor preserves the current working-frame behavior and appearance. It does not authorize a production deployment or changes to live financial data.

## Context

The Transaction Explorer working frame now proves the intended product flow:

- Personal and Green Capital Investing can be selected independently or together.
- Entity, year, month, type, WDG, JPW, and search filters feed one filtered transaction set.
- The metrics, rollup, and ledger show the same filtered set.
- Each slicer supports select all, clear all, and single or multiple selection.
- The frame runs on an isolated Docker2 container and the disposable `sure_frame_preview` database.

The first implementation correctly proves the behavior, but responsibility is spread across three places:

- `Myfin::TransactionExplorerQuery` builds rows, filter options, and flat rollup rows.
- `Myfin::TransactionExplorersController` parses selected values and calculates metrics.
- `show.html.erb` calculates type totals, WDG totals, and the rollup hierarchy while rendering.

The raw filter hash also exposes the hidden `__none__` form value to the query implementation. The query loads and maps the accessible entry set twice, once for filter options and again for selected rows.

## Goal

Create one deep reporting module whose small interface returns every data structure the Transaction Explorer page renders. The module must load the accessible transaction dataset once, preserve entity-allocation amounts, and make the shared-set guarantee structural.

## Non-goals

- No visual redesign.
- No new slicers, saved views, exports, or editing actions.
- No change to the current transaction-type interpretation.
- No production deployment.
- No live MyFIN data mutation.
- No full SQL aggregation rewrite before profiling proves it is needed.
- No removal of the test-only preview login until the working frame is no longer needed.

## External interface

The page controller will use one reporting interface:

```ruby
filters = Myfin::TransactionExplorer::Filters.from_params(params)
report = Myfin::TransactionExplorer::Report.call(
  user: Current.user,
  filters: filters
)
```

`Report.call` returns a `Result` with:

```ruby
Result = Data.define(
  :rows,
  :metrics,
  :rollup,
  :filter_options,
  :selected_filters
)
```

Callers do not calculate totals, group rows, interpret the no-selection sentinel, or rebuild selected filter values.

## Filters module

`Myfin::TransactionExplorer::Filters` is an immutable value object. Its interface is:

```ruby
filters = Myfin::TransactionExplorer::Filters.from_params(params)
filters.values_for(:entity_ids)
filters.values_for(:years)
filters.values_for(:months)
filters.values_for(:types)
filters.values_for(:wdg_categories)
filters.values_for(:jpw_categories)
filters.search
filters.explicit?(:years)
filters.selected_values(:years, available: [2025, 2026])
```

Rules:

- An absent filter means all available values.
- The hidden form sentinel `__none__` means an explicit empty selection.
- The sentinel never leaves the Filters implementation.
- Blank values are ignored.
- Years and months normalize to integers.
- Entity IDs and category or type values normalize to strings.
- Unknown entity IDs are removed when the report scopes them to active entities in the user's family.
- `selected_values` returns strings because HTML checkbox values are strings.

## Report module

`Myfin::TransactionExplorer::Report` owns the full reporting implementation.

### Dataset loading

The report loads accessible transaction entries once using:

- `entryable_type = "Transaction"`
- the user's accessible accounts
- active family entity allocations
- preloaded account, allocation entity, category scheme, and scheme category associations

The relation must remain family and account scoped. The report does not accept an arbitrary relation from the controller.

### Allocation handling

The report creates an internal source row per entry. A source row retains allocations by entity. When entities are selected, the displayed amount is the inverse of the selected allocation sum so the page retains its current display convention:

- expenses are negative
- income is positive
- incoming transfers are positive
- outgoing transfers are negative

This preserves correct partial-allocation behavior when a future transaction belongs to more than one entity.

### Type handling

The current working-frame behavior remains unchanged:

- `funds_movement` and `cc_payment` are `Transfer`
- other negative allocation amounts are `Income`
- other zero or positive allocation amounts are `Expense`

Loan-payment and investment-contribution semantics remain a separate product decision.

### Row filtering

The report applies filters to source rows in this order:

1. selected entities and their allocation amounts
2. year
3. month
4. type
5. WDG category
6. JPW category
7. normalized search across description, account, WDG, JPW, and entity names

Rows sort by date descending, then entry ID for deterministic output.

### Metrics

The report derives metrics from the final `rows` array:

```ruby
Metrics = Data.define(:transactions, :expenses, :income, :transfer_net)
```

- `transactions` is the row count.
- `expenses` is the sum of absolute Expense amounts.
- `income` is the signed sum of Income amounts.
- `transfer_net` is the signed sum of Transfer amounts.

### Hierarchical rollup

The report converts the final rows into a render-ready hierarchy:

```ruby
RollupType = Data.define(:type, :amount, :groups)
RollupGroup = Data.define(:wdg, :amount, :categories)
RollupCategory = Data.define(:jpw, :amount, :count)
```

Ordering remains:

- Expense, Income, Transfer
- WDG groups by absolute amount descending, then name
- JPW categories by absolute amount descending, then name

The view does not call `group_by`, `sum`, or interpret transaction types.

### Filter options

Filter options come from the complete accessible source-row set before selected filters are applied. This allows an unselected entity or category to remain available for re-selection.

```ruby
FilterOptions = Data.define(
  :entities,
  :years,
  :months,
  :types,
  :wdg_categories,
  :jpw_categories
)
```

Entities include only active family entities with at least one accessible allocated row.

### Selected filters

The report returns render-ready selected strings for every slicer. The controller and partial do not reconstruct defaults.

## Controller

`Myfin::TransactionExplorersController#show` becomes an adapter between Rails and the reporting interface. It will:

1. create `Filters` from permitted request parameters
2. call `Report`
3. assign the report and the first 250 ledger rows
4. set breadcrumbs

The controller will not calculate metrics, group rollups, or understand the no-selection sentinel.

## Views

The current page is split into focused rendering partials:

- `_filters.html.erb` owns the GET form, search, category disclosure, and slicer partial calls.
- `_metrics.html.erb` renders `report.metrics`.
- `_rollup.html.erb` renders `report.rollup`.
- `_ledger.html.erb` renders the first 250 `report.rows`.
- `_slicer.html.erb` remains the reusable slicer window.
- `show.html.erb` composes the page and shared-set proof strip.

The partial split is for locality. It introduces no new rendering interface beyond the `report` result.

## Preview authentication

The preview login remains a test-only adapter:

- its route exists only when `Rails.env.test?`
- it requires `TRANSACTION_EXPLORER_PREVIEW_LOGIN=1`
- it requires `TRANSACTION_EXPLORER_PREVIEW_USER_EMAIL`
- it never appears in production routes

It must be removed before the feature is merged as a normal production route unless a later decision explicitly retains test preview infrastructure.

## Performance

The immediate requirement is to remove the duplicate entry load and mapping pass. The refactored report may continue Ruby-side filtering for the current dataset size.

After the structural refactor, measure report construction against the live-sized restored or representative dataset. Move date, entity, and category filtering or aggregation into SQL only if the measurement justifies it. Do not create a second SQL adapter in advance.

## Error and empty states

- No available rows returns empty metrics, rollup, ledger, and filter options.
- Clear all on any slicer returns zero filtered rows while keeping the slicer options available.
- Invalid or cross-family entity IDs produce zero selected entity rows and never widen access.
- Missing WDG or JPW classifications display as `Uncategorized`.
- A blocked browser session store affects only single or multiple mode persistence, not filtering.

## Verification

Automated checks must prove:

- Personal and GCI together return 20 sample rows.
- Personal only returns 12 sample rows.
- Rollup, metrics, and ledger use the same final row set.
- Partial entity allocations use only selected allocation amounts.
- An explicit empty slicer selection returns zero rows.
- Unselected entities and categories remain available as filter options.
- The controller renders without recalculating report values.
- The preview sign-in remains test-only and flag-gated.
- JavaScript single, multiple, select-all, and clear-all behavior remains green.

Browser verification must confirm the current frame at `http://100.104.3.101:8950/myfin/transaction_explorer` is visually unchanged and retains the 20-row and 12-row checkpoints.

## Rollback

The work stays on `codex/transaction-explorer-frame`. The isolated preview continues to use `sure_frame_preview`. Rollback consists of returning the branch to the last working-frame commit and recreating only `myfin-transaction-explorer-frame`; no production container or live database is involved.
