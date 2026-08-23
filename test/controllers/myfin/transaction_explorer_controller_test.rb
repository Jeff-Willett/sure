require "test_helper"

class MyfinTransactionExplorerControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:family_admin)
    @family = @user.family
    Myfin::BootstrapFamily.call(family: @family)
    @personal = @family.myfin_entities.find_by!(name: "JPW Personal")
    @gci = @family.myfin_entities.find_by!(name: "Green Capital Investing")
    sign_in @user
  end

  test "renders one shared filtered set in the rollup and ledger" do
    personal_entry = create_classified_entry(
      account: accounts(:depository),
      entity: @personal,
      date: Date.new(2026, 8, 5),
      name: "Frame visible personal expense",
      amount: 120,
      wdg: "Shopping",
      jpw: "Groceries"
    )
    gci_entry = create_classified_entry(
      account: accounts(:credit_card),
      entity: @gci,
      date: Date.new(2026, 8, 6),
      name: "Frame hidden GCI expense",
      amount: 75,
      wdg: "GCI Office Expense",
      jpw: "GCI Business Software"
    )

    get myfin_transaction_explorer_path, params: {
      entity_ids: [ @personal.id ],
      years: [ 2026 ],
      months: [ 8 ]
    }

    assert_response :success
    assert_select "h1", text: "Transaction Explorer"
    assert_select "input[name='entity_ids[]'][value='#{@personal.id}']", checked: "checked"
    assert_select "input[name='entity_ids[]'][value='#{@gci.id}']", count: 1
    assert_select "[data-testid='transaction-explorer-shared-set'][data-ledger-count='1'][data-rollup-count='1']"
    assert_select "tr[data-entry-id='#{personal_entry.id}']", count: 1
    assert_select "tr[data-entry-id='#{gci_entry.id}']", count: 0
    assert_select "a[href='#{myfin_transaction_explorer_path}']", text: /Explorer/
    assert_select "button[aria-label^='Reporting profile:']", count: 0
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
