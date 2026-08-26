require "test_helper"

class MyfinTransactionExplorerControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:family_admin)
    @family = @user.family
    Myfin::BootstrapFamily.call(family: @family)
    @personal = @family.myfin_entities.find_by!(name: "JPW Personal")
    @donna = @family.myfin_entities.find_by!(name: "Donna")
    @gci = @family.myfin_entities.find_by!(name: "Green Capital Investing")
    sign_in @user
  end

  test "entity filters can combine entities regardless of the global reporting profile" do
    personal_entry = create_classified_entry(
      account: accounts(:depository),
      entity: @personal,
      date: Date.new(2026, 8, 5),
      name: "Combined JPW expense",
      amount: 120,
      wdg: "Shopping",
      jpw: "Shopping"
    )
    donna_entry = create_classified_entry(
      account: accounts(:credit_card),
      entity: @donna,
      date: Date.new(2026, 8, 6),
      name: "Combined Donna expense",
      amount: 75,
      wdg: nil,
      jpw: "Shopping"
    )
    gci_profile = @family.myfin_reporting_profiles.find_by!(name: "Green Capital Investing")
    patch myfin_reporting_profile_path, params: { profile_id: gci_profile.id }

    get myfin_transaction_explorer_path, params: {
      entity_ids: [ @personal.id, @donna.id ],
      years: [ 2026 ],
      months: [ 8 ]
    }

    assert_response :success
    assert tabulator_row(personal_entry)
    assert tabulator_row(donna_entry)
    assert_select "input[name='entity_ids[]'][value='#{@personal.id}']", checked: "checked"
    assert_select "input[name='entity_ids[]'][value='#{@donna.id}']", checked: "checked"
    assert_select "button[aria-label^='Reporting profile:']", count: 0
  end

  test "uses compact JPW and CGI display labels" do
    personal_entry = create_classified_entry(
      account: accounts(:depository),
      entity: @personal,
      date: Date.new(2026, 8, 5),
      name: "Compact JPW label",
      amount: 40,
      wdg: "Shopping",
      jpw: "Shopping"
    )
    gci_entry = create_classified_entry(
      account: accounts(:credit_card),
      entity: @gci,
      date: Date.new(2026, 8, 6),
      name: "Compact CGI label",
      amount: 25,
      wdg: nil,
      jpw: "Business Software"
    )

    get myfin_transaction_explorer_path

    assert_response :success
    assert_select "fieldset[data-transaction-explorer-slicer-key-value='entity_ids']", text: /JPW/, count: 1
    assert_select "fieldset[data-transaction-explorer-slicer-key-value='entity_ids']", text: /CGI/, count: 1
    assert_select "fieldset[data-transaction-explorer-slicer-key-value='entity_ids']", text: /JPW Personal|Green Capital Investing/, count: 0
    assert_equal "JPW", tabulator_row(personal_entry).fetch("entity")
    assert_equal "CGI", tabulator_row(gci_entry).fetch("entity")
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
    assert_includes response.body, '"utils/tag_input"'
    assert_select "h1.sr-only", text: "Transaction Explorer"
    assert_select "main", text: /Working frame/, count: 0
    assert_select "input[name='entity_ids[]'][value='#{@personal.id}']", checked: "checked"
    assert_select "input[name='entity_ids[]'][value='#{@gci.id}']", count: 1
    assert_select "fieldset[data-controller='transaction-explorer-slicer']", minimum: 4 do |slicers|
      slicers.each do |slicer|
        assert_select slicer, "input[type='hidden'][value='__none__']", count: 1
        assert_select slicer, "button[aria-label='Select all']", count: 1
        assert_select slicer, "button[aria-label='Clear all']", count: 1
        assert_select slicer, "button[aria-label='Use single selection']", count: 1
      end
    end
    assert_select "[data-testid='transaction-explorer-shared-set']", count: 0
    assert_select "#transaction-explorer-metrics", count: 0
    assert_select "[data-controller='transaction-explorer-tabulator']", count: 1
    assert_select "[data-action='transaction-explorer-tabulator#toggleLayout']", text: "Layout", count: 1
    assert_select "[data-action='transaction-explorer-tabulator#fitColumns']", text: /Fit columns/i, count: 1
    assert_select "[data-action='transaction-explorer-tabulator#collapseAll']", text: /Collapse all/i, count: 1
    assert_select "[role='separator'][aria-label='Resize the assistant sidebar'] span.bg-secondary", count: 1
    assert_select "[data-testid='responsive-navigation-drawer']", count: 1
    assert_select "[data-testid='compact-navigation-rail']", count: 1 do
      assert_select "[data-action='app-layout#openMobileSidebar']", count: 1
    end
    assert_equal "Groceries", tabulator_row(personal_entry).fetch("detail_category")
    assert_nil tabulator_row(gci_entry)
    assert_select "a[href='#{myfin_transaction_explorer_path}']", text: /Explorer/
    assert_select "button[aria-label^='Reporting profile:']", count: 0
  end

  test "keeps the category panel open after a category filter submission" do
    category = @family.myfin_category_schemes.find_by!(name: "JPW")
      .scheme_categories.create!(name: "Panel category")
    get myfin_transaction_explorer_path, params: {
      detail_category_ids: [ category.id ]
    }

    assert_response :success
    assert_select "details[open]", count: 1 do
      assert_select "summary", text: /Categories and tags/
    end
  end

  test "renders a full-height persistent Tabulator grid with desktop controls" do
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
    assert_select "main[class*='overflow-hidden'][class*='min-h-0']", count: 1
    assert_select "[data-controller='transaction-explorer-tabulator'][data-transaction-explorer-tabulator-persistence-id-value='myfin-transaction-explorer-v3']", count: 1 do
      assert_select "[data-transaction-explorer-tabulator-target='grid']", count: 1
      assert_select "[data-transaction-explorer-tabulator-target='sort']", count: 1
      assert_select "button", text: "Layout", count: 1
      assert_select "button[data-action='transaction-explorer-tabulator#toggleRollups'][aria-expanded='false']", text: "Rollups", count: 1
      assert_select "button", text: /Fit columns/i, count: 1
      assert_select "button", text: /Collapse all/i, count: 1
      assert_select "button", text: "Undo", count: 1
      assert_select "button", text: "Redo", count: 1
      assert_select "aside[hidden][data-transaction-explorer-tabulator-target='rollupPane']", count: 1
    end
    row = tabulator_row(entry)
    assert_equal "Shopping", row.fetch("wdg_rollup")
    assert_equal "Groceries", row.fetch("detail_category")
    assert_equal myfin_entry_transaction_explorer_classification_path(entry), row.fetch("category_update_url")
    assert_equal tags_transaction_path(entry), row.fetch("tag_update_url")
    assert row.fetch("scheme_id").present?
    assert_select "template[data-transaction-explorer-tabulator-target='categoryData']", count: 1
    assert_select "template[data-transaction-explorer-tabulator-target='tagData']", count: 1
  end


  test "renders JPW, WDG, and GCI categories in separate filter buckets" do
    create_classified_entry(
      account: accounts(:depository),
      entity: @personal,
      date: Date.new(2026, 8, 12),
      name: "JPW category bucket",
      amount: 40,
      wdg: "Shopping",
      jpw: "Restaurants"
    )
    create_classified_entry(
      account: accounts(:credit_card),
      entity: @gci,
      date: Date.new(2026, 8, 12),
      name: "GCI category bucket",
      amount: 25,
      wdg: nil,
      jpw: "Business Software"
    )

    get myfin_transaction_explorer_path

    assert_response :success
    assert_select "fieldset[data-category-catalog='JPW']", count: 1 do
      assert_select "input[name='detail_category_ids[]']", minimum: 1
      assert_select "label", text: /Restaurants/, minimum: 1
      assert_select "label", text: /Business Software/, count: 0
    end
    assert_select "fieldset[data-category-catalog='WDG']", count: 1
    assert_select "fieldset[data-category-catalog='GCI']", count: 1 do
      assert_select "label", text: /Business Software/, minimum: 1
      assert_select "label", text: /Restaurants/, count: 0
    end
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
    assert tabulator_row(editable_entry).fetch("editable")
    assert_not tabulator_row(read_only_entry).fetch("editable")
  end

  test "renders tag filters and names active exclusions" do
    setup_tag = @family.tags.create!(name: "Apartment Setup 2026", color: "#e99537")
    entry = create_classified_entry(
      account: accounts(:depository),
      entity: @personal,
      date: Date.new(2026, 8, 8),
      name: "Tagged grid expense",
      amount: 45,
      wdg: "Shopping",
      jpw: "Groceries"
    )
    entry.transaction.tags << setup_tag

    get myfin_transaction_explorer_path, params: { exclude_tag_ids: [ setup_tag.id ] }

    assert_response :success
    assert_select "input[name='exclude_tag_ids[]'][value='#{setup_tag.id}'][checked]", count: 1
    assert_select "input[name='include_tag_ids[]'][value='#{setup_tag.id}']", count: 1
    assert_select "[data-testid='transaction-explorer-active-exclusions']", text: /Apartment Setup 2026/, count: 1
    assert_select "tr[data-entry-id='#{entry.id}']", count: 0
  end

  test "entity filters replace profile scoping while preserving GCI editing" do
    entry = create_classified_entry(
      account: accounts(:credit_card),
      entity: @gci,
      date: Date.new(2026, 8, 9),
      name: "GCI profile expense",
      amount: 25,
      wdg: "Ignored WDG",
      jpw: "Business Software"
    )
    select_profile("Green Capital Investing")

    get myfin_transaction_explorer_path

    assert_response :success
    assert_equal "CGI", tabulator_row(entry).fetch("entity")
    assert_equal "Business Software", tabulator_row(entry).fetch("detail_category")
  end

  test "Everything keeps same-named JPW and DIS categories separate" do
    jpw_entry = create_classified_entry(
      account: accounts(:depository),
      entity: @personal,
      date: Date.new(2026, 8, 10),
      name: "JPW Shopping example",
      amount: 90,
      wdg: "Shopping",
      jpw: "Shared display Shopping"
    )
    donna = @family.myfin_entities.find_by!(name: "Donna")
    donna_entry = create_classified_entry(
      account: accounts(:credit_card),
      entity: donna,
      date: Date.new(2026, 8, 10),
      name: "Donna Shopping example",
      amount: 50,
      wdg: "Ignored WDG",
      jpw: "Shared display Shopping"
    )
    select_profile("Everything")

    get myfin_transaction_explorer_path

    assert_response :success
    assert_equal "Shared display Shopping", tabulator_row(jpw_entry).fetch("detail_category")
    assert_equal "Shared display Shopping", tabulator_row(donna_entry).fetch("detail_category")
    assert_not_equal tabulator_row(jpw_entry).fetch("entity"), tabulator_row(donna_entry).fetch("entity")
  end

  test "global WDG profile does not hide other entities from Explorer" do
    personal_entry = create_classified_entry(
      account: accounts(:depository),
      entity: @personal,
      date: Date.new(2026, 8, 11),
      name: "WDG personal example",
      amount: 90,
      wdg: "Shopping",
      jpw: "Restaurants"
    )
    gci_entry = create_classified_entry(
      account: accounts(:credit_card),
      entity: @gci,
      date: Date.new(2026, 8, 11),
      name: "WDG excluded GCI example",
      amount: 25,
      wdg: "Ignored WDG",
      jpw: "Business Software"
    )
    select_profile("WDG Report")

    get myfin_transaction_explorer_path

    assert_response :success
    assert tabulator_row(personal_entry)
    assert tabulator_row(gci_entry)
    assert_select "input[name='wdg_rollup_ids[]']", minimum: 1
  end

  test "renders scoped history for editable rows and recent changes in the drawer" do
    entry = create_classified_entry(
      account: accounts(:depository),
      entity: @personal,
      date: Date.new(2026, 8, 10),
      name: "History affordance expense",
      amount: 45,
      wdg: "Shopping",
      jpw: "Groceries"
    )

    read_only_account = Account.create!(
      family: @family,
      owner: users(:family_member),
      name: "History read-only checking",
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
    read_only_entry = create_classified_entry(
      account: read_only_account,
      entity: @personal,
      date: Date.new(2026, 8, 11),
      name: "History hidden expense",
      amount: 30,
      wdg: "Shopping",
      jpw: "Groceries"
    )

    get myfin_transaction_explorer_path

    assert_response :success
    assert_not tabulator_row(entry).key?("open_url")
    assert_not tabulator_row(read_only_entry).fetch("editable")
  end

  test "renders the committed change ID in the edit result for undo" do
    scheme = @family.myfin_category_schemes.find_by!(name: "JPW")
    old_category = scheme.scheme_categories.create!(name: "Undo original category")
    new_category = scheme.scheme_categories.create!(name: "Undo updated category")
    entry = create_classified_entry(
      account: accounts(:depository),
      entity: @personal,
      date: Date.new(2026, 8, 12),
      name: "Undo result expense",
      amount: 55,
      wdg: "Shopping",
      jpw: old_category.name
    )

    patch myfin_entry_transaction_explorer_classification_path(entry), params: {
      scheme_id: scheme.id,
      category_id: new_category.id,
      expected_category_id: old_category.id
    }, as: :turbo_stream

    change = Myfin::ClassificationChange.order(:created_at, :id).last

    assert_response :success
    assert_select "turbo-stream[action='update'][target='transaction-explorer-edit-result'] template [data-entry-id='#{entry.id}'][data-scheme='JPW'][data-change-id='#{change.id}'][data-scheme-id='#{scheme.id}'][data-previous-category-id='#{old_category.id}'][data-new-category-id='#{new_category.id}'][data-revert-url='#{revert_myfin_classification_change_path(change)}']", count: 1
  end

  private
    def rendered_tabulator_rows
      node = css_select("template[data-transaction-explorer-tabulator-target='data']").first
      JSON.parse(node.content)
    end

    def tabulator_row(entry)
      rendered_tabulator_rows.find { |row| row.fetch("id") == entry.id }
    end

    def select_profile(name)
      profile = @family.myfin_reporting_profiles.find_by!(name: name)
      patch myfin_reporting_profile_path,
        params: { profile_id: profile.id },
        headers: { "HTTP_REFERER" => myfin_transaction_explorer_url }
      assert_response :redirect
    end

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
      detail_scheme = entity.category_schemes.find_by!(is_default: true)
      detail_category = detail_scheme.scheme_categories.find_or_create_by!(name: jpw)
      Myfin::Imports::ClassificationWriter.call(
        sure_transaction: entry.transaction,
        classifications: { detail_scheme.name => detail_category.name }
      )
      if entity == @personal
        wdg_category = @family.myfin_category_schemes.find_by!(name: "WDG")
          .scheme_categories.find_or_create_by!(name: wdg)
        Myfin::CategoryRollupMapping.find_or_create_by!(source_category: detail_category) do |mapping|
          mapping.target_category = wdg_category
        end
      end
      entry
    end
end
