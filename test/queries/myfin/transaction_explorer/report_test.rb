require "test_helper"

class MyfinTransactionExplorerReportTest < ActiveSupport::TestCase
  setup do
    @user = users(:family_admin)
    @family = @user.family
    Myfin::BootstrapFamily.call(family: @family)
    @personal = @family.myfin_entities.find_by!(name: "JPW Personal")
    @gci = @family.myfin_entities.find_by!(name: "Green Capital Investing")
  end

  test "loads entries once and preserves selected allocation amounts" do
    personal_entry = create_entry(
      entity_amounts: { @personal => 40 },
      date: Date.new(2026, 8, 6),
      name: "Report personal expense",
      amount: 40
    )
    shared_entry = create_entry(
      entity_amounts: { @personal => 60, @gci => 40 },
      date: Date.new(2026, 8, 5),
      name: "Report shared expense",
      amount: 100
    )
    filters = Myfin::TransactionExplorer::Filters.from_params(
      entity_ids: [ @personal.id ], years: [ "2026" ], months: [ "8" ]
    )

    report = Myfin::TransactionExplorer::Report.call(user: @user, filters: filters)

    assert_equal [ personal_entry.id, shared_entry.id ], report.rows.map(&:entry_id)
    assert_equal(-60.to_d, report.rows.find { |row| row.entry_id == shared_entry.id }.amount)
    assert_equal 2, report.metrics.transactions
    assert_equal report.rows.sum(&:amount), report.rollup.sum(&:amount)

    ActiveRecord::Base.connection.clear_query_cache
    queries = capture_sql_queries do
      Myfin::TransactionExplorer::Report.call(user: @user, filters: filters)
    end
    entry_loads = queries.count { |sql| sql.include?('FROM "entries"') && sql.include?("entryable_type") }
    assert_equal 1, entry_loads
  end

  test "uses one filtered row set for rollup and deterministic ordering" do
    personal_expense = create_entry(
      entity_amounts: { @personal => 120 },
      date: Date.new(2026, 8, 5),
      name: "Frame personal expense",
      amount: 120,
      wdg: "Shopping",
      jpw: "Groceries"
    )
    personal_income = create_entry(
      entity_amounts: { @personal => -3000 },
      date: Date.new(2026, 8, 14),
      name: "Frame personal income",
      amount: -3000,
      wdg: "Transfer",
      jpw: "Income"
    )
    create_entry(
      entity_amounts: { @gci => 75 },
      date: Date.new(2026, 8, 6),
      name: "Frame GCI expense",
      amount: 75,
      account: accounts(:credit_card),
      wdg: "GCI Office Expense",
      jpw: "GCI Business Software"
    )
    filters = Myfin::TransactionExplorer::Filters.from_params(
      entity_ids: [ @personal.id ],
      years: [ "2026" ],
      months: [ "8" ],
      types: %w[Expense Income]
    )

    report = Myfin::TransactionExplorer::Report.call(user: @user, filters: filters)

    assert_equal [ personal_income.id, personal_expense.id ], report.rows.map(&:entry_id)
    rollup_rows = report.rollup.flat_map do |type|
      type.groups.flat_map do |group|
        group.categories.map { |category| [ type.type, group.wdg, category.jpw, category.amount, category.count ] }
      end
    end

    assert_equal [
      [ "Expense", "Shopping", "Groceries", -120.to_d, 1 ],
      [ "Income", "Transfer", "Income", 3000.to_d, 1 ]
    ], rollup_rows
    assert_equal report.rows.sum(&:amount), report.rollup.sum(&:amount)
  end

  test "available slicers retain unselected entities and classification values" do
    create_entry(
      entity_amounts: { @personal => 120 },
      date: Date.new(2026, 8, 5),
      name: "Frame personal option",
      amount: 120,
      wdg: "Shopping",
      jpw: "Groceries"
    )
    create_entry(
      entity_amounts: { @gci => 75 },
      date: Date.new(2025, 6, 6),
      name: "Frame GCI option",
      amount: 75,
      account: accounts(:credit_card),
      wdg: "GCI Office Expense",
      jpw: "GCI Business Software"
    )
    filters = Myfin::TransactionExplorer::Filters.from_params(entity_ids: [ @personal.id ])

    report = Myfin::TransactionExplorer::Report.call(user: @user, filters: filters)

    assert_equal [
      [ @gci.id, "Green Capital Investing" ],
      [ @personal.id, "JPW Personal" ]
    ], report.filter_options.entities
    assert_equal [ 2025, 2026 ], report.filter_options.years
    assert_equal [ 6, 8 ], report.filter_options.months
    assert_equal [ "GCI Office Expense", "Shopping" ], report.filter_options.wdg_categories
    assert_equal [ "GCI Business Software", "Groceries" ], report.filter_options.jpw_categories
    assert_equal({
      entity_ids: [ @personal.id.to_s ],
      years: %w[2025 2026],
      months: %w[6 8],
      types: [ "Expense" ],
      wdg_categories: [ "GCI Office Expense", "Shopping" ],
      jpw_categories: [ "GCI Business Software", "Groceries" ]
    }, report.selected_filters)
  end

  test "returns metrics and a hierarchical rollup from the final rows" do
    create_entry(
      entity_amounts: { @personal => 120 },
      date: Date.new(2026, 8, 5),
      name: "Report expense",
      amount: 120,
      wdg: "Shopping",
      jpw: "Groceries"
    )
    create_entry(
      entity_amounts: { @personal => -3000 },
      date: Date.new(2026, 8, 6),
      name: "Report income",
      amount: -3000,
      wdg: "Transfer",
      jpw: "Income"
    )
    create_entry(
      entity_amounts: { @personal => -500 },
      date: Date.new(2026, 8, 7),
      name: "Report transfer",
      amount: -500,
      kind: "funds_movement",
      wdg: "Transfers",
      jpw: "Transfers"
    )
    filters = Myfin::TransactionExplorer::Filters.from_params(years: [ "2026" ])

    report = Myfin::TransactionExplorer::Report.call(user: @user, filters: filters)

    assert_equal 3, report.metrics.transactions
    assert_equal 120.to_d, report.metrics.expenses
    assert_equal 3000.to_d, report.metrics.income
    assert_equal 500.to_d, report.metrics.transfer_net

    assert_equal [ "Expense", "Income", "Transfer" ], report.rollup.map(&:type)
    assert_equal "Shopping", report.rollup.first.groups.first.wdg
    assert_equal "Groceries", report.rollup.first.groups.first.categories.first.jpw
  end

  test "keeps available years when an explicit empty year selection clears rows" do
    create_entry(
      entity_amounts: { @personal => 120 },
      date: Date.new(2026, 8, 5),
      name: "Report current year",
      amount: 120
    )
    create_entry(
      entity_amounts: { @personal => 80 },
      date: Date.new(2025, 8, 5),
      name: "Report prior year",
      amount: 80
    )
    filters = Myfin::TransactionExplorer::Filters.from_params(years: [ "__none__" ])

    report = Myfin::TransactionExplorer::Report.call(user: @user, filters: filters)

    assert_empty report.rows
    assert_equal 0, report.metrics.transactions
    assert_equal BigDecimal("0"), report.metrics.expenses
    assert_equal BigDecimal("0"), report.metrics.income
    assert_equal BigDecimal("0"), report.metrics.transfer_net
    assert_empty report.rollup
    assert_equal [ 2025, 2026 ], report.filter_options.years
  end

  test "does not widen entity scope for a cross-family entity id" do
    other_entity = families(:empty).myfin_entities.create!(name: "Other Family Entity", entity_type: "person", active: true)
    personal_entry = create_entry(
      entity_amounts: { @personal => 120 },
      date: Date.new(2026, 8, 5),
      name: "Report scoped expense",
      amount: 120
    )
    filters = Myfin::TransactionExplorer::Filters.from_params(entity_ids: [ @personal.id, other_entity.id ])

    report = Myfin::TransactionExplorer::Report.call(user: @user, filters: filters)

    assert_equal [ personal_entry.id ], report.rows.map(&:entry_id)
    assert_equal [ @personal.id ], report.rows.first.entity_ids
  end

  test "exposes missing classifications as uncategorized" do
    entry = create_entry(
      entity_amounts: { @personal => 120 },
      date: Date.new(2026, 8, 5),
      name: "Report uncategorized expense",
      amount: 120
    )
    report = Myfin::TransactionExplorer::Report.call(
      user: @user,
      filters: Myfin::TransactionExplorer::Filters.from_params({})
    )

    row = report.rows.find { |candidate| candidate.entry_id == entry.id }
    assert_equal "Uncategorized", row.wdg
    assert_equal "Uncategorized", row.jpw
  end

  test "exposes editor metadata and all active category options outside the current filters" do
    wdg_scheme = @family.myfin_category_schemes.find_by!(name: "WDG")
    jpw_scheme = @family.myfin_category_schemes.find_by!(name: "JPW")
    wdg_category = wdg_scheme.scheme_categories.create!(name: "Report metadata WDG category")
    jpw_category = jpw_scheme.scheme_categories.create!(name: "Report metadata JPW category")
    available_only_in_editor = wdg_scheme.scheme_categories.create!(name: "Explorer-only WDG category")
    wdg_scheme.scheme_categories.create!(name: "Inactive Explorer category", active: false)
    entry = create_entry(
      entity_amounts: { @personal => 120 },
      date: Date.new(2026, 8, 5),
      name: "Report editor metadata",
      amount: 120,
      wdg: wdg_category.name,
      jpw: jpw_category.name
    )

    report = Myfin::TransactionExplorer::Report.call(
      user: @user,
      filters: Myfin::TransactionExplorer::Filters.from_params(wdg_categories: [ wdg_category.name ])
    )

    row = report.rows.find { |candidate| candidate.entry_id == entry.id }
    assert_equal entry.transaction_id, row.transaction_id
    assert_equal wdg_category.id, row.wdg_category_id
    assert_equal jpw_category.id, row.jpw_category_id
    assert row.editable
    assert_includes report.category_options.fetch("WDG"), [ available_only_in_editor.id, available_only_in_editor.name ]
    assert_not_includes report.category_options.fetch("WDG"), [ wdg_scheme.scheme_categories.find_by!(name: "Inactive Explorer category").id, "Inactive Explorer category" ]
  end

  test "marks rows from read-only accounts as not editable" do
    wdg_scheme = @family.myfin_category_schemes.find_by!(name: "WDG")
    jpw_scheme = @family.myfin_category_schemes.find_by!(name: "JPW")
    wdg_category = wdg_scheme.scheme_categories.create!(name: "Read-only metadata WDG category")
    jpw_category = jpw_scheme.scheme_categories.create!(name: "Read-only metadata JPW category")
    create_entry(
      entity_amounts: { @personal => 120 },
      date: Date.new(2026, 8, 5),
      name: "Report read-only editor metadata",
      amount: 120,
      account: accounts(:credit_card),
      wdg: wdg_category.name,
      jpw: jpw_category.name
    )

    report = Myfin::TransactionExplorer::Report.call(
      user: users(:family_member),
      filters: Myfin::TransactionExplorer::Filters.from_params({})
    )

    row = report.rows.find { |candidate| candidate.description == "Report read-only editor metadata" }
    assert_not row.editable
  end

  private
    def create_entry(entity_amounts:, date:, name:, amount:, account: accounts(:depository), kind: "standard", wdg: nil, jpw: nil)
      entry = account.entries.create!(
        entryable: Transaction.new(kind: kind),
        date: date,
        name: name,
        amount: amount,
        currency: "USD"
      )
      Myfin::EntryAllocation.replace_for!(entry, entity_amounts.map do |entity, entity_amount|
        Myfin::EntryAllocation.new(
          entity: entity,
          amount: entity_amount,
          allocation_source: "manual"
        )
      end)
      classifications = { "WDG" => wdg, "JPW" => jpw }.compact
      Myfin::Imports::ClassificationWriter.call(sure_transaction: entry.transaction, classifications:) if classifications.present?
      entry
    end
end
