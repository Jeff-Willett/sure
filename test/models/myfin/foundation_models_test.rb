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

  test "one JPW category has at most one WDG target" do
    family = families(:dylan_family)
    source = scheme_category(family:, scheme_name: "JPW", category_name: "Restaurants")
    first_target = scheme_category(family:, scheme_name: "WDG", category_name: "Shopping")
    second_target = scheme_category(family:, scheme_name: "WDG", category_name: "Other Living Expenses")

    Myfin::CategoryRollupMapping.create!(
      source_category: source,
      target_category: first_target
    )
    duplicate = Myfin::CategoryRollupMapping.new(
      source_category: source,
      target_category: second_target
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:source_category_id], "has already been taken"
  end

  test "DIS and GCI categories cannot map to WDG" do
    family = families(:dylan_family)
    wdg = scheme_category(family:, scheme_name: "WDG", category_name: "Shopping")

    %w[DIS GCI].each do |scheme_name|
      mapping = Myfin::CategoryRollupMapping.new(
        source_category: scheme_category(family:, scheme_name:, category_name: "Shopping"),
        target_category: wdg
      )

      assert_not mapping.valid?
      assert_includes mapping.errors[:source_category], "must belong to the JPW scheme"
    end
  end

  test "a rollup target must be a WDG category in the same family" do
    family = families(:dylan_family)
    source = scheme_category(family:, scheme_name: "JPW", category_name: "Restaurants")
    wrong_scheme = scheme_category(family:, scheme_name: "GCI", category_name: "Office Expense")
    other_family_target = scheme_category(
      family: families(:empty),
      scheme_name: "WDG",
      category_name: "Shopping"
    )

    wrong_target = Myfin::CategoryRollupMapping.new(source_category: source, target_category: wrong_scheme)
    cross_family = Myfin::CategoryRollupMapping.new(source_category: source, target_category: other_family_target)

    assert_not wrong_target.valid?
    assert_includes wrong_target.errors[:target_category], "must belong to the WDG scheme"
    assert_not cross_family.valid?
    assert_includes cross_family.errors[:target_category], "must belong to the source category family"
  end

  private
    def scheme_category(family:, scheme_name:, category_name:)
      scheme = family.myfin_category_schemes.find_or_create_by!(name: scheme_name)
      scheme.scheme_categories.find_or_create_by!(name: category_name)
    end
end
