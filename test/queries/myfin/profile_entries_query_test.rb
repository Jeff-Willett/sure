require "test_helper"

class MyfinProfileEntriesQueryTest < ActiveSupport::TestCase
  setup do
    @user = users(:family_admin)
    @family = @user.family
    Myfin::BootstrapFamily.call(family: @family)
    @gci = @family.myfin_entities.find_by!(name: "Green Capital Investing")
    @personal = @family.myfin_entities.find_by!(name: "JPW Personal")
    @profile = @family.myfin_reporting_profiles.find_by!(name: "Green Capital Investing")
  end

  test "returns only allocated entries in accessible accounts" do
    gci_entry = create_entry(accounts(:depository), "GCI purchase")
    personal_entry = create_entry(accounts(:credit_card), "Personal purchase")
    allocate(gci_entry, @gci)
    allocate(personal_entry, @personal)

    relation = Myfin::ProfileEntriesQuery.call(user: @user, profile: @profile)

    assert_equal [ gci_entry.id ], relation.order(:id).pluck(:id)
  end

  test "rejects a profile from another family" do
    other_profile = Myfin::ReportingProfile.create!(
      family: families(:empty),
      name: "Other family",
      is_default: true
    )

    assert_raises(Myfin::ProfileEntriesQuery::ProfileFamilyMismatch) do
      Myfin::ProfileEntriesQuery.call(user: @user, profile: other_profile)
    end
  end

  private
    def create_entry(account, name)
      account.entries.create!(
        entryable: Transaction.new,
        name: name,
        date: Date.current,
        amount: 10,
        currency: "USD"
      )
    end

    def allocate(entry, entity)
      Myfin::EntryAllocation.create!(
        entry: entry,
        entity: entity,
        amount: entry.amount,
        allocation_source: "manual"
      )
    end
end
