require "application_system_test_case"

class MyfinTransactionExplorerAmountsTest < ApplicationSystemTestCase
  setup do
    @user = users(:family_admin)
    @family = @user.family
    Myfin::BootstrapFamily.call(family: @family)
    Entry.delete_all

    @entity = @family.myfin_entities.find_by!(name: "JPW Personal")
    @entry = accounts(:depository).entries.create!(
      entryable: Transaction.new,
      amount: 0.21,
      currency: "USD",
      date: Date.new(2026, 8, 27),
      name: "Production-shaped fractional expense"
    )
    Myfin::EntryAllocation.replace_for!(@entry, [
      Myfin::EntryAllocation.new(
        entity: @entity,
        amount: @entry.amount,
        allocation_source: "manual"
      )
    ])

    sign_in @user
  end

  test "keeps decimal-dollar amounts after the in-memory working set loads" do
    visit myfin_transaction_explorer_path(
      entity_ids: [ @entity.id ],
      years: [ 2026 ],
      months: [ 8 ],
      types: [ "Expense" ]
    )

    row = find("[role='row']", text: @entry.name)
    assert_no_selector(
      "form[data-transaction-explorer-tabulator-target='form'][aria-busy='true']",
      wait: 10
    )

    assert_includes row.text, "-$0.21"
    refute_includes row.text, "-$0.00"
  end
end
