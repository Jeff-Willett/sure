require "test_helper"

class MyfinClassificationChangeTest < ActiveSupport::TestCase
  setup do
    @transaction = transactions(:one)
    @family = @transaction.entry.account.family
    @scheme = Myfin::CategoryScheme.create!(family: @family, name: "Personal")
    @old_category = Myfin::SchemeCategory.create!(category_scheme: @scheme, name: "Dining")
    @new_category = Myfin::SchemeCategory.create!(category_scheme: @scheme, name: "Coffee")
  end

  test "records an edit with immutable category snapshots" do
    change = build_change(previous: @old_category, new: @new_category)

    assert change.save
    assert_equal change, @transaction.myfin_classification_changes.find(change.id)
    assert_equal @old_category.name, change.previous_category_name
    assert_equal @new_category.name, change.new_category_name
    assert_not change.update(action: "revert")
    assert_equal "edit", change.reload.action
    assert_not change.destroy
    assert change.reload.persisted?
  end

  test "represents uncategorized with a nil id and name pair" do
    change = build_change(previous: @old_category, new: nil)

    assert change.valid?
    change.new_category_name = "orphaned label"
    assert_not change.valid?
  end

  test "rejects a caller-supplied category name that does not match the category" do
    change = build_change(
      previous: @old_category,
      new: @new_category,
      previous_name: "Incorrect label"
    )

    assert_no_difference -> { Myfin::ClassificationChange.count } do
      assert_not change.save
    end
    assert_includes change.errors[:previous_category_name], "must match the category name"
  end

  test "preserves a saved category name after the category is renamed or deleted" do
    change = build_change(previous: @old_category, new: @new_category)
    assert change.save

    @old_category.update!(name: "Restaurants")
    @new_category.update!(name: "Cafes")
    assert_equal "Dining", change.reload.previous_category_name
    assert_equal "Coffee", change.new_category_name

    @old_category.destroy!
    assert_nil change.reload.previous_category_id
    assert_equal "Dining", change.previous_category_name

    @new_category.destroy!
    assert_nil change.reload.new_category_id
    assert_equal "Coffee", change.new_category_name
  end

  test "requires the transaction to belong to the change family" do
    other_family = Family.create!(name: "Other family")
    change = build_change(previous: @old_category, new: @new_category, family: other_family)

    assert_not change.valid?
    assert_includes change.errors[:transaction], "must belong to the change family"
  end

  test "requires the category scheme to belong to the change family" do
    other_family = Family.create!(name: "Other family")
    other_scheme = Myfin::CategoryScheme.create!(family: other_family, name: "Other scheme")
    other_category = Myfin::SchemeCategory.create!(category_scheme: other_scheme, name: "Other category")
    change = build_change(
      previous: other_category,
      new: other_category,
      category_scheme: other_scheme
    )

    assert_not change.valid?
    assert_includes change.errors[:category_scheme], "must belong to the change family"
  end

  test "requires categories to belong to the declared category scheme" do
    other_scheme = Myfin::CategoryScheme.create!(family: @family, name: "Shared family scheme")
    other_category = Myfin::SchemeCategory.create!(category_scheme: other_scheme, name: "Other category")
    change = build_change(previous: other_category, new: other_category)

    assert_not change.valid?
    assert_includes change.errors[:previous_category], "must belong to the declared category scheme"
    assert_includes change.errors[:new_category], "must belong to the declared category scheme"
  end

  private
    def build_change(
      previous:,
      new:,
      family: @family,
      category_scheme: @scheme,
      previous_name: previous&.name,
      new_name: new&.name
    )
      Myfin::ClassificationChange.new(
        family: family,
        sure_transaction: @transaction,
        category_scheme: category_scheme,
        actor: users(:family_admin),
        previous_category: previous,
        previous_category_name: previous_name,
        new_category: new,
        new_category_name: new_name,
        action: "edit",
        source: "transaction_explorer"
      )
    end
end
