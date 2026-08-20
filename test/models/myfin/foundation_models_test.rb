require "test_helper"

class MyfinFoundationModelsTest < ActiveSupport::TestCase
  test "an account entity must belong to the account family" do
    account = accounts(:depository)
    other_family = Family.create!(name: "Other")
    entity = Myfin::Entity.create!(family: other_family, name: "Other entity", entity_type: "person")

    membership = Myfin::AccountEntity.new(
      account: account,
      entity: entity,
      ownership_percent: 100
    )

    assert_not membership.valid?
    assert_includes membership.errors[:entity], "must belong to the account family"
  end

  test "entry allocations must total the entry amount" do
    entry = entries(:transaction)
    entity = Myfin::Entity.create!(
      family: entry.account.family,
      name: "JPW Personal",
      entity_type: "person"
    )
    allocation = Myfin::EntryAllocation.new(
      entry: entry,
      entity: entity,
      amount: entry.amount - 1,
      allocation_source: "manual"
    )

    assert_raises(Myfin::AllocationTotalError) do
      Myfin::EntryAllocation.replace_for!(entry, [ allocation ])
    end
    assert_empty entry.myfin_allocations.reload
  end

  test "entry allocations are replaced atomically" do
    entry = entries(:transaction)
    entity = Myfin::Entity.create!(
      family: entry.account.family,
      name: "JPW Personal",
      entity_type: "person"
    )

    Myfin::EntryAllocation.replace_for!(entry, [
      Myfin::EntryAllocation.new(
        entry: entry,
        entity: entity,
        amount: entry.amount,
        allocation_source: "account_default"
      )
    ])

    assert_equal 1, entry.myfin_allocations.reload.count
    assert_equal entry.amount, entry.myfin_allocations.first.amount
  end

  test "a classification category must belong to its declared scheme" do
    transaction = transactions(:one)
    family = transaction.entry.account.family
    jpw = Myfin::CategoryScheme.create!(family: family, name: "JPW")
    wdg = Myfin::CategoryScheme.create!(family: family, name: "WDG")
    wdg_category = Myfin::SchemeCategory.create!(category_scheme: wdg, name: "Shopping")

    classification = Myfin::TransactionClassification.new(
      sure_transaction: transaction,
      category_scheme: jpw,
      scheme_category: wdg_category,
      classification_source: "imported",
      confidence: 1
    )

    assert_not classification.valid?
    assert_includes classification.errors[:scheme_category], "must belong to the declared category scheme"
  end

  test "a reporting profile cannot include another family's entity" do
    profile = Myfin::ReportingProfile.create!(
      family: families(:dylan_family),
      name: "My Personal Finances"
    )
    other_family = Family.create!(name: "Other")
    entity = Myfin::Entity.create!(family: other_family, name: "Other entity", entity_type: "person")

    membership = Myfin::ReportingProfileEntity.new(
      reporting_profile: profile,
      entity: entity
    )

    assert_not membership.valid?
    assert_includes membership.errors[:entity], "must belong to the reporting profile family"
  end
end
