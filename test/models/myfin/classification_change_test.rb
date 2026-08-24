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
    assert_equal @old_category.name, change.previous_category_name
    assert_equal @new_category.name, change.new_category_name
    assert_not change.update(action: "revert")
    assert_not change.destroy
  end

  test "represents uncategorized with a nil id and name pair" do
    change = build_change(previous: @old_category, new: nil)

    assert change.valid?
    change.new_category_name = "orphaned label"
    assert_not change.valid?
  end

  private
    def build_change(previous:, new:)
      Myfin::ClassificationChange.new(
        family: @family,
        transaction: @transaction,
        category_scheme: @scheme,
        actor: users(:family_admin),
        previous_category: previous,
        previous_category_name: previous&.name,
        new_category: new,
        new_category_name: new&.name,
        action: "edit",
        source: "transaction_explorer"
      )
    end
end
