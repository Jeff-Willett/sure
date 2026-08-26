require "application_system_test_case"

class MyfinReportingProfilesTest < ApplicationSystemTestCase
  setup do
    @user = users(:family_admin)
    @family = @user.family
    Myfin::BootstrapFamily.call(family: @family)
    Entry.delete_all

    @personal_entity = @family.myfin_entities.find_by!(name: "JPW Personal")
    @business_entity = @family.myfin_entities.find_by!(name: "Green Capital Investing")
    @personal_entry = create_entry(accounts(:depository), "Personal profile transaction", @personal_entity)
    @business_entry = create_entry(accounts(:credit_card), "GCI profile transaction", @business_entity)

    sign_in @user
  end

  test "switches reporting profiles without changing ownership" do
    visit transactions_path

    assert_text @personal_entry.name
    assert_no_text @business_entry.name

    click_button "JPW Personal"
    click_button "Green Capital Investing"

    assert_text @business_entry.name
    assert_no_text @personal_entry.name

    click_button "Green Capital Investing"
    click_button "Everything"

    assert_text @personal_entry.name
    assert_text @business_entry.name
    assert_equal @personal_entity, @personal_entry.myfin_allocations.reload.first.entity
    assert_equal @business_entity, @business_entry.myfin_allocations.reload.first.entity
  end

  private
    def create_entry(account, name, entity)
      entry = account.entries.create!(
        entryable: Transaction.new,
        amount: 10,
        currency: "USD",
        date: Date.current,
        name: name
      )
      Myfin::EntryAllocation.replace_for!(entry, [
        Myfin::EntryAllocation.new(entity: entity, amount: entry.amount, allocation_source: "manual")
      ])
      entry
    end
end
