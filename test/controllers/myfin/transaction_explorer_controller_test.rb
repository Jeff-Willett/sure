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
    assert_select "h1.sr-only", text: "Transaction Explorer"
    assert_select "main", text: /Working frame/, count: 0
    assert_select "input[name='entity_ids[]'][value='#{@personal.id}']", checked: "checked"
    assert_select "input[name='entity_ids[]'][value='#{@gci.id}']", count: 1
    assert_select "fieldset[data-controller='transaction-explorer-slicer']", count: 6 do |slicers|
      slicers.each do |slicer|
        assert_select slicer, "input[type='hidden'][value='__none__']", count: 1
        assert_select slicer, "button[aria-label='Select all']", count: 1
        assert_select slicer, "button[aria-label='Clear all']", count: 1
        assert_select slicer, "button[aria-label='Use single selection']", count: 1
      end
    end
    assert_select "[data-testid='transaction-explorer-shared-set'][data-ledger-count='1'][data-rollup-count='1']"
    assert_select "[data-controller~='transaction-explorer-split']", count: 1
    assert_select "[role='separator'][aria-label='Resize rollup panel']", count: 1
    assert_select "[role='separator'][aria-label='Resize the assistant sidebar'] span.bg-secondary", count: 1
    assert_select "[data-testid='responsive-navigation-drawer']", count: 1
    assert_select "[data-testid='compact-navigation-rail']", count: 1 do
      assert_select "[data-action='app-layout#openMobileSidebar']", count: 1
    end
    assert_select "section", text: /Transactions\s+1\s+Expenses\s+\$120\.00\s+Income\s+\$0\.00\s+Transfer net\s+\$0\.00/
    assert_select "section", text: /Expense\s+\$120\.00.*Shopping\s+\$120\.00.*Groceries\s+\$120\.00/m
    assert_select "a[href*='wdg_categories'] span[aria-hidden='true']", count: 0
    assert_select "a[href*='jpw_categories'] span[aria-hidden='true']", text: "🛒", minimum: 1
    assert_select "tr[data-entry-id='#{personal_entry.id}']", count: 1
    assert_select "tr[data-entry-id='#{gci_entry.id}']", count: 0
    assert_select "a[href='#{myfin_transaction_explorer_path}']", text: /Explorer/
    assert_select "button[aria-label^='Reporting profile:']", count: 0
  end

  test "keeps the category panel open after a category filter submission" do
    get myfin_transaction_explorer_path, params: {
      jpw_categories: [ "Renter Expenses" ]
    }

    assert_response :success
    assert_select "details[open]", count: 1 do
      assert_select "summary", text: /WDG and JPW categories/
    end
  end

  test "renders a semantic resizable category grid with edit controls" do
    entry = create_classified_entry(
      account: accounts(:depository),
      entity: @personal,
      date: Date.new(2026, 8, 7),
      name: "Resizable grid expense",
      amount: 120,
      wdg: "Shopping",
      jpw: "Groceries"
    )

    get myfin_transaction_explorer_path, params: { search: "grid" }

    assert_response :success
    assert_select "div[data-controller~='transaction-explorer-grid']", count: 1 do
      assert_select "colgroup[data-transaction-explorer-columns-target='colgroup'] col[data-column]", count: 7
      assert_select "thead th", count: 7 do |headers|
        headers.each do |header|
          assert_select header, "[data-transaction-explorer-columns-target='handle'][tabindex='0']", count: 1
        end
      end
      assert_select "td[data-entry-id='#{entry.id}'][data-scheme='WDG'][data-transaction-explorer-grid-target='cell'] form", count: 1
      assert_select "td[data-entry-id='#{entry.id}'][data-scheme='JPW'][data-transaction-explorer-grid-target='cell'] form", count: 1
      assert_select "td[data-entry-id='#{entry.id}'][data-scheme='WDG'] form[action*='search=grid'] input[name='scheme_id']", count: 1
      assert_select "td[data-entry-id='#{entry.id}'][data-scheme='WDG'] form select[name='category_id'] option[value='']", text: "Uncategorized", count: 1
      assert_select "td[data-entry-id='#{entry.id}'][data-scheme='WDG'] form select[name='category_id'] option[value=''][selected]", count: 0
      assert_select "th[data-column='date'][style*='transaction-explorer-date-offset']", count: 1
      assert_select "th[data-column='entity'][style*='transaction-explorer-entity-offset']", count: 1
    end
    assert_select "#transaction-explorer-ledger[data-controller~='transaction-explorer-grid']", count: 0
    assert_select "tr[data-entry-id='#{entry.id}'] td:first-child[style*='transaction-explorer-date-offset']", count: 1
    assert_select "tr[data-entry-id='#{entry.id}'] td:nth-child(2)[style*='transaction-explorer-entity-offset']", count: 1
    assert_select "button", text: "Edit categories", count: 1
    assert_select "button", text: "Recent changes", count: 1
    assert_select "button", text: "Reset column widths", count: 1
  end

  test "renders category editors only for editable rows" do
    read_only_account = Account.create!(
      family: @family,
      owner: users(:family_member),
      name: "Read-only checking",
      balance: 0,
      currency: "USD",
      accountable_type: "Depository",
      accountable: Depository.create!(subtype: "checking")
    )
    read_only_account.account_shares.create!(
      user: @user,
      permission: "read_only",
      include_in_finances: true
    )
    read_only_account.myfin_account_entities.create!(entity: @personal)

    editable_entry = create_classified_entry(
      account: accounts(:depository),
      entity: @personal,
      date: Date.new(2026, 8, 8),
      name: "Editable grid expense",
      amount: 45,
      wdg: "Shopping",
      jpw: "Groceries"
    )
    read_only_entry = create_classified_entry(
      account: read_only_account,
      entity: @personal,
      date: Date.new(2026, 8, 9),
      name: "Read-only grid expense",
      amount: 30,
      wdg: "Shopping",
      jpw: "Groceries"
    )

    get myfin_transaction_explorer_path

    assert_response :success
    assert_select "tr[data-entry-id='#{editable_entry.id}'] td[data-scheme] form", count: 2
    assert_select "tr[data-entry-id='#{read_only_entry.id}'] td[data-scheme] form", count: 0
    assert_select "tr[data-entry-id='#{read_only_entry.id}'] td[data-scheme] [data-editor]", count: 0
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
