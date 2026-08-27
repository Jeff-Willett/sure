require "test_helper"

class MyfinEntityCategoryContextTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)
    Myfin::BootstrapFamily.call(family: @family)
    @jpw = @family.myfin_entities.find_by!(name: "JPW Personal")
    @donna = @family.myfin_entities.find_by!(name: "Donna")
    @gci = @family.myfin_entities.find_by!(name: "Green Capital Investing")
    @jpw_scheme = @family.myfin_category_schemes.find_by!(name: "JPW")
    @dis_scheme = @family.myfin_category_schemes.find_by!(name: "DIS")
    @gci_scheme = @family.myfin_category_schemes.find_by!(name: "GCI")
    @wdg_scheme = @family.myfin_category_schemes.find_by!(name: "WDG")
    @restaurants = @jpw_scheme.scheme_categories.create!(name: "Restaurants")
    @wdg_shopping = @wdg_scheme.scheme_categories.create!(name: "Shopping")
    @jpw_shopping = @jpw_scheme.scheme_categories.create!(name: "Shopping")
    @dis_shopping = @dis_scheme.scheme_categories.create!(name: "Shopping")
    Myfin::CategoryRollupMapping.create!(
      source_category: @restaurants,
      target_category: @wdg_shopping
    )
  end

  test "resolves a JPW category and its WDG rollup" do
    entry = classified_entry(entity: @jpw, scheme: @jpw_scheme, category: @restaurants)

    result = Myfin::EntityCategoryContext.call(entry: entry)

    assert_equal "ready", result.status
    assert_equal @jpw, result.entity
    assert_equal @jpw_scheme, result.scheme
    assert_equal @restaurants, result.detail_category
    assert_equal @wdg_shopping, result.wdg_rollup
  end

  test "keeps same-named JPW and DIS categories distinct" do
    Myfin::CategoryRollupMapping.create!(
      source_category: @jpw_shopping,
      target_category: @wdg_shopping
    )
    jpw_result = Myfin::EntityCategoryContext.call(
      entry: classified_entry(entity: @jpw, scheme: @jpw_scheme, category: @jpw_shopping)
    )
    dis_result = Myfin::EntityCategoryContext.call(
      entry: classified_entry(entity: @donna, scheme: @dis_scheme, category: @dis_shopping)
    )

    assert_equal "Shopping", jpw_result.detail_category.name
    assert_equal "Shopping", dis_result.detail_category.name
    assert_not_equal jpw_result.detail_category.id, dis_result.detail_category.id
    assert_nil dis_result.wdg_rollup
    assert_equal "ready", dis_result.status
  end

  test "marks an entry without an allocation as needing an entity" do
    entry = create_entry

    result = Myfin::EntityCategoryContext.call(entry: entry)

    assert_equal "needs_entity", result.status
    assert_nil result.entity
    assert_nil result.scheme
  end

  test "marks split allocations for review" do
    entry = create_entry(amount: 100)
    Myfin::EntryAllocation.replace_for!(entry, [
      allocation(entity: @jpw, amount: 60),
      allocation(entity: @gci, amount: 40)
    ])

    result = Myfin::EntityCategoryContext.call(entry: entry)

    assert_equal "split_allocation", result.status
    assert_nil result.entity
    assert_nil result.detail_category
  end

  test "marks an entity-owned entry without a detail category" do
    entry = create_entry
    Myfin::EntryAllocation.replace_for!(entry, [ allocation(entity: @donna, amount: entry.amount) ])

    result = Myfin::EntityCategoryContext.call(entry: entry)

    assert_equal "needs_category", result.status
    assert_equal @donna, result.entity
    assert_equal @dis_scheme, result.scheme
  end

  test "marks a JPW category without a WDG mapping" do
    entry = classified_entry(entity: @jpw, scheme: @jpw_scheme, category: @jpw_shopping)

    result = Myfin::EntityCategoryContext.call(entry: entry)

    assert_equal "needs_wdg_mapping", result.status
    assert_equal @jpw_shopping, result.detail_category
    assert_nil result.wdg_rollup
  end

  test "does not use a classification from another entity catalog" do
    entry = classified_entry(entity: @donna, scheme: @jpw_scheme, category: @jpw_shopping)

    result = Myfin::EntityCategoryContext.call(entry: entry)

    assert_equal "needs_category", result.status
    assert_equal @dis_scheme, result.scheme
    assert_nil result.classification
  end

  test "uses preloaded category schemes without another query" do
    entry = classified_entry(entity: @jpw, scheme: @jpw_scheme, category: @restaurants)
    preloaded_entry = Entry
      .includes(
        myfin_allocations: { entity: :category_schemes },
        entryable: { myfin_classifications: { scheme_category: :wdg_rollup_category } }
      )
      .find(entry.id)

    queries = capture_sql_queries do
      result = Myfin::EntityCategoryContext.call(entry: preloaded_entry)
      assert_equal @jpw_scheme, result.scheme
      assert_equal @restaurants, result.detail_category
    end

    scheme_queries = queries.grep(/FROM "myfin_category_schemes"/)
    assert_empty scheme_queries
  end

  private
    def classified_entry(entity:, scheme:, category:)
      entry = create_entry
      Myfin::EntryAllocation.replace_for!(entry, [ allocation(entity: entity, amount: entry.amount) ])
      Myfin::TransactionClassification.create!(
        sure_transaction: entry.transaction,
        category_scheme: scheme,
        scheme_category: category,
        classification_source: "manual",
        confidence: 1
      )
      entry
    end

    def create_entry(amount: 25)
      accounts(:depository).entries.create!(
        entryable: Transaction.new,
        date: Date.new(2026, 8, 26),
        name: "Context sample",
        amount: amount,
        currency: "USD"
      )
    end

    def allocation(entity:, amount:)
      Myfin::EntryAllocation.new(
        entity: entity,
        amount: amount,
        allocation_source: "manual"
      )
    end
end
