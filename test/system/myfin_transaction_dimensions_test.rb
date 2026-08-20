require "application_system_test_case"

class MyfinTransactionDimensionsTest < ApplicationSystemTestCase
  setup do
    @user = users(:family_admin)
    @family = @user.family
    Myfin::BootstrapFamily.call(family: @family)
    @personal_entity = @family.myfin_entities.find_by!(name: "JPW Personal")
    @business_entity = @family.myfin_entities.find_by!(name: "Green Capital Investing")
    @entry = entries(:transaction)
    Myfin::EntryAllocation.replace_for!(@entry, [
      Myfin::EntryAllocation.new(entity: @personal_entity, amount: @entry.amount, allocation_source: "manual")
    ])
    @jpw_scheme = @family.myfin_category_schemes.find_by!(name: "JPW")
    @wdg_scheme = @family.myfin_category_schemes.find_by!(name: "WDG")
    @jpw_category = Myfin::SchemeCategory.create!(category_scheme: @jpw_scheme, name: "Dining")
    @wdg_category = Myfin::SchemeCategory.create!(category_scheme: @wdg_scheme, name: "Restaurants")
    @entry.transaction.tags << tags(:one)

    sign_in @user
  end

  test "edits allocations and parallel categories without removing Sure tags" do
    visit transaction_path(@entry)
    find("summary", text: /MyFIN dimensions/i, match: :first).click

    within "form[action='#{myfin_entry_allocation_path(@entry)}']" do
      select @business_entity.name, from: "myfin_allocation_entity_0"
      fill_in "myfin_allocation_amount_0", with: @entry.amount.to_s
      click_button "Save ownership"
    end

    find("summary", text: /MyFIN dimensions/i, match: :first).click
    find("summary", text: /JPW, WDG, and source categories/i).click
    within "form[action='#{myfin_transaction_classifications_path(@entry.transaction)}']" do
      select @jpw_category.name, from: find("label", exact_text: "JPW")[:for]
      select @wdg_category.name, from: find("label", exact_text: "WDG")[:for]
      click_button "Save categories"
    end

    visit transaction_path(@entry)
    find("summary", text: /MyFIN dimensions/i, match: :first).click
    find("summary", text: /JPW, WDG, and source categories/i).click

    assert_equal @business_entity, @entry.myfin_allocations.reload.first.entity
    assert_equal @jpw_category, @entry.transaction.myfin_classifications.reload.find_by!(category_scheme: @jpw_scheme).scheme_category
    assert_equal @wdg_category, @entry.transaction.myfin_classifications.find_by!(category_scheme: @wdg_scheme).scheme_category
    assert_includes @entry.transaction.tags.reload, tags(:one)
  end
end
