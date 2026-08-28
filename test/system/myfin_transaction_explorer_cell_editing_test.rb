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

  test "drag selects cells vertically without selecting page text" do
    visit_explorer
    source = find("[role='gridcell']", text: @category.name, exact_text: true)
    target = find("[role='gridcell']", text: @third_category.name, exact_text: true)

    drag_result = page.execute_script(<<~JS, source, target)
      const source = arguments[0];
      const target = arguments[1];
      const categoryCells = [...document.querySelectorAll(
        "[tabulator-field='detail_category_id']",
      )];
      const expectedCount = Math.abs(
        categoryCells.indexOf(target) - categoryCells.indexOf(source),
      ) + 1;
      const text = document.querySelector("[tabulator-field='description']");
      const range = document.createRange();
      range.selectNodeContents(text);
      window.getSelection().removeAllRanges();
      window.getSelection().addRange(range);

      source.dispatchEvent(new MouseEvent("mousedown", {
        bubbles: true,
        cancelable: true,
        button: 0,
        buttons: 1,
      }));
      const selectionAllowed = target.dispatchEvent(new Event("selectstart", {
        bubbles: true,
        cancelable: true,
      }));
      target.dispatchEvent(new MouseEvent("mouseover", {
        bubbles: true,
        cancelable: true,
        buttons: 1,
      }));
      document.dispatchEvent(new MouseEvent("mouseup", {
        bubbles: true,
        cancelable: true,
        button: 0,
      }));
      return { expectedCount, selectionAllowed };
    JS

    assert_equal false, drag_result.fetch("selectionAllowed")
    assert_equal drag_result.fetch("expectedCount"),
      all(".myfin-cell-selected[tabulator-field='detail_category_id']").size
    assert_equal 0,
      all(".myfin-cell-selected[tabulator-field='tags']").size
    assert_equal "", page.evaluate_script("window.getSelection().toString()")
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
