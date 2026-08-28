require "application_system_test_case"

class MyfinTransactionExplorerCellEditingTest < ApplicationSystemTestCase
  setup do
    @user = users(:family_admin)
    @family = @user.family
    Myfin::BootstrapFamily.call(family: @family)
    Entry.delete_all
    @entity = @family.myfin_entities.find_by!(name: "JPW Personal")
    @scheme = @family.myfin_category_schemes.find_by!(name: "JPW")
    @category = @scheme.scheme_categories.create!(name: "Click selected category")
    @second_category = @scheme.scheme_categories.create!(name: "Paste target two")
    @third_category = @scheme.scheme_categories.create!(name: "Paste target three")
    @entry = create_entry("Spreadsheet click behavior", @category)
    @second_entry = create_entry("Spreadsheet paste target two", @second_category)
    @third_entry = create_entry("Spreadsheet paste target three", @third_category)
    sign_in @user
  end

  test "single click selects the category cell and double click opens its editor" do
    visit myfin_transaction_explorer_path(
      entity_ids: [ @entity.id ],
      years: [ 2026 ],
      months: [ 8 ],
      types: [ "Expense" ]
    )

    cell = find("[role='gridcell']", text: @category.name, exact_text: true)
    cell.click
    assert_no_selector ".tabulator-cell.tabulator-editing", wait: 0.5
    assert_selector ".tabulator-cell.myfin-cell-selected"

    cell.double_click
    assert_selector ".tabulator-cell.tabulator-editing"
  end

  test "right click opens the category editor" do
    visit_explorer

    find("[role='gridcell']", text: @category.name, exact_text: true).right_click

    assert_selector ".tabulator-cell.tabulator-editing"
  end

  test "pastes one copied category into a selected range" do
    visit_explorer
    find("[role='gridcell']", text: @second_category.name, exact_text: true).click
    find("[role='gridcell']", text: @third_category.name, exact_text: true).click(:shift)

    clipboard_payload = {
      fields: [ "detail_category" ],
      rows: [ [ { categoryId: @category.id, label: @category.name } ] ]
    }
    page.execute_script(<<~JS, clipboard_payload)
      const data = new DataTransfer();
      data.setData("application/x-myfin-explorer+json", JSON.stringify(arguments[0]));
      data.setData("text/plain", arguments[0].rows[0][0].label);
      const event = new ClipboardEvent("paste", {
        bubbles: true,
        cancelable: true,
        clipboardData: data,
      });
      document.querySelector("[data-transaction-explorer-tabulator-target='grid']")
        .dispatchEvent(event);
    JS

    assert_selector "[role='gridcell']", text: @category.name, exact_text: true, count: 3
    assert_equal @category,
      @second_entry.transaction.myfin_classifications.reload.find_by!(category_scheme: @scheme).scheme_category
    assert_equal @category,
      @third_entry.transaction.myfin_classifications.reload.find_by!(category_scheme: @scheme).scheme_category
  end

  private
    def visit_explorer
      visit myfin_transaction_explorer_path(
        entity_ids: [ @entity.id ],
        years: [ 2026 ],
        months: [ 8 ],
        types: [ "Expense" ]
      )
    end

    def create_entry(name, category)
      entry = accounts(:depository).entries.create!(
        entryable: Transaction.new,
        date: Date.new(2026, 8, 27),
        name: name,
        amount: 25,
        currency: "USD"
      )
      Myfin::EntryAllocation.replace_for!(entry, [
        Myfin::EntryAllocation.new(entity: @entity, amount: entry.amount, allocation_source: "manual")
      ])
      Myfin::Imports::ClassificationWriter.call(
        sure_transaction: entry.transaction,
        classifications: { "JPW" => category.name }
      )
      entry
    end
end
