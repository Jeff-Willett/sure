require "test_helper"

class MyfinPreviewDatasetTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)
  end

  test "creates separate Shopping categories and apartment event tags idempotently" do
    first = Myfin::PreviewDataset.call(family: @family)
    second = Myfin::PreviewDataset.call(family: @family)

    jpw_shopping = @family.myfin_category_schemes.find_by!(name: "JPW")
      .scheme_categories.find_by!(name: "Shopping")
    dis_shopping = @family.myfin_category_schemes.find_by!(name: "DIS")
      .scheme_categories.find_by!(name: "Shopping")

    assert_not_equal jpw_shopping.id, dis_shopping.id
    assert_equal 1, @family.tags.where(name: "Apartment Setup 2026").count
    assert_equal first.transaction_ids.sort, second.transaction_ids.sort
    assert_equal 5, first.transaction_ids.size
    assert_equal 5, @family.transactions.where(id: first.transaction_ids).count
  end

  test "creates JPW mappings while Donna and GCI remain unmapped" do
    result = Myfin::PreviewDataset.call(family: @family)
    contexts = @family.entries.where(entryable_id: result.transaction_ids).map do |entry|
      Myfin::EntityCategoryContext.call(entry: entry)
    end

    jpw_contexts = contexts.select { |context| context.entity.name == "JPW Personal" }
    donna_context = contexts.find { |context| context.entity.name == "Donna" }
    gci_context = contexts.find { |context| context.entity.name == "Green Capital Investing" }

    assert jpw_contexts.all? { |context| context.wdg_rollup.present? }
    assert_nil donna_context.wdg_rollup
    assert_nil gci_context.wdg_rollup
    assert_equal "DIS", donna_context.scheme.name
    assert_equal "GCI", gci_context.scheme.name
  end

  test "uses fictional names and marks apartment transactions" do
    result = Myfin::PreviewDataset.call(family: @family)
    entries = @family.entries.where(entryable_id: result.transaction_ids)

    assert_equal [
      "Sample Business Software",
      "Sample Cafe",
      "Sample Donna Store",
      "Sample Home Store",
      "Sample Online Market"
    ], entries.order(:name).pluck(:name)
    tagged_names = entries.select do |entry|
      entry.transaction.tags.any? { |tag| tag.name == "Apartment Setup 2026" }
    end.map(&:name).sort
    assert_equal [ "Sample Home Store", "Sample Online Market" ], tagged_names
  end
end
