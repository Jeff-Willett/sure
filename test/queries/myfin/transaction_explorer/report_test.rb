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

  private
    def create_entry(entity_amounts:, date:, name:, amount:, account: accounts(:depository), kind: "standard")
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
      entry
    end
end
