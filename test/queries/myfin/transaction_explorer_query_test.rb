require "test_helper"

class MyfinTransactionExplorerQueryTest < ActiveSupport::TestCase
  setup do
    @user = users(:family_admin)
    @family = @user.family
    Myfin::BootstrapFamily.call(family: @family)
    @personal = @family.myfin_entities.find_by!(name: "JPW Personal")
    @gci = @family.myfin_entities.find_by!(name: "Green Capital Investing")
  end

  test "ledger rows and rollup totals come from the same filtered entries" do
    personal_expense = create_classified_entry(
      account: accounts(:depository),
      entity: @personal,
      date: Date.new(2026, 8, 5),
      name: "Frame personal expense",
      amount: 120,
      wdg: "Shopping",
      jpw: "Groceries"
    )
    personal_income = create_classified_entry(
      account: accounts(:depository),
      entity: @personal,
      date: Date.new(2026, 8, 14),
      name: "Frame personal income",
      amount: -3000,
      wdg: "Transfer",
      jpw: "Income"
    )
    create_classified_entry(
      account: accounts(:credit_card),
      entity: @gci,
      date: Date.new(2026, 8, 6),
      name: "Frame GCI expense",
      amount: 75,
      wdg: "GCI Office Expense",
      jpw: "GCI Business Software"
    )

    result = Myfin::TransactionExplorerQuery.call(
      user: @user,
      filters: {
        entity_ids: [ @personal.id ],
        years: [ 2026 ],
        months: [ 8 ],
        types: %w[Expense Income]
      }
    )

    assert_equal [ personal_income.id, personal_expense.id ], result.rows.map(&:entry_id)
    assert_equal [
      [ "Expense", "Shopping", "Groceries", -120.to_d, 1 ],
      [ "Income", "Transfer", "Income", 3000.to_d, 1 ]
    ], result.rollup_rows.map { |row| [ row.type, row.wdg, row.jpw, row.amount, row.count ] }
    assert_equal result.rows.sum(&:amount), result.rollup_rows.sum(&:amount)
  end

  test "available slicers retain unselected entities and classification values" do
    create_classified_entry(
      account: accounts(:depository),
      entity: @personal,
      date: Date.new(2026, 8, 5),
      name: "Frame personal option",
      amount: 120,
      wdg: "Shopping",
      jpw: "Groceries"
    )
    create_classified_entry(
      account: accounts(:credit_card),
      entity: @gci,
      date: Date.new(2025, 6, 6),
      name: "Frame GCI option",
      amount: 75,
      wdg: "GCI Office Expense",
      jpw: "GCI Business Software"
    )

    result = Myfin::TransactionExplorerQuery.call(
      user: @user,
      filters: { entity_ids: [ @personal.id ] }
    )

    assert_equal [
      [ @gci.id, "Green Capital Investing" ],
      [ @personal.id, "JPW Personal" ]
    ], result.filter_options.entities
    assert_equal [ 2025, 2026 ], result.filter_options.years
    assert_equal [ 6, 8 ], result.filter_options.months
    assert_equal [ "GCI Office Expense", "Shopping" ], result.filter_options.wdg_categories
    assert_equal [ "GCI Business Software", "Groceries" ], result.filter_options.jpw_categories
  end

  private
    def create_classified_entry(account:, entity:, date:, name:, amount:, wdg:, jpw:)
      entry = account.entries.create!(
        entryable: Transaction.new,
        date: date,
        name: name,
        amount: amount,
        currency: "USD"
      )
      Myfin::EntryAllocation.replace_for!(entry, [
        Myfin::EntryAllocation.new(
          entity: entity,
          amount: entry.amount,
          allocation_source: "manual"
        )
      ])
      Myfin::Imports::ClassificationWriter.call(
        sure_transaction: entry.transaction,
        classifications: { "WDG" => wdg, "JPW" => jpw }
      )
      entry
    end
end
