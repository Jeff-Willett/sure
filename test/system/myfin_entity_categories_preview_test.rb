require "application_system_test_case"

class MyfinEntityCategoriesPreviewTest < ApplicationSystemTestCase
  setup do
    @user = users(:family_admin)
    @family = @user.family
    Entry.delete_all
    Myfin::PreviewDataset.call(family: @family)
    sign_in @user
  end

  test "excludes an apartment event without recategorizing Shopping" do
    setup_tag = @family.tags.find_by!(name: "Apartment Setup 2026")

    visit myfin_transaction_explorer_path

    assert_text "Sample Online Market"
    assert_text "Sample Home Store"
    assert_text "Sample Cafe"
    assert_text "Shopping"

    find("summary", text: "Categories and tags").click
    page.execute_script(<<~JS)
      const input = document.querySelector(
        "input[name='exclude_tag_ids[]'][value='#{setup_tag.id}']"
      );
      input.checked = true;
      input.dispatchEvent(new Event("change", { bubbles: true }));
    JS

    assert_no_text "Sample Online Market"
    assert_no_text "Sample Home Store"
    assert_text "Sample Cafe"
    assert_text "Shopping"
    assert_text "Excluding: Apartment Setup 2026"
  end
end
