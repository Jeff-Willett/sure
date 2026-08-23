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
    create_entry(
      entity_amounts: { @personal => 120 },
      date: Date.new(2026, 8, 5),
      name: "Report scoped expense",
      amount: 120
    )
    filters = Myfin::TransactionExplorer::Filters.from_params(entity_ids: [ other_entity.id ])

    report = Myfin::TransactionExplorer::Report.call(user: @user, filters: filters)

    assert_empty report.rows
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
