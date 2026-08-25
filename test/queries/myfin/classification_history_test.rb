require "test_helper"

class MyfinClassificationHistoryTest < ActiveSupport::TestCase
  setup do
    @user = users(:family_member)
    @family = @user.family
    @accessible_account = accounts(:depository)
    @inaccessible_account = accounts(:investment)
    @inaccessible_account.account_shares.where(user: @user).destroy_all

    @scheme = Myfin::CategoryScheme.create!(family: @family, name: "JPW")
    @previous_category = Myfin::SchemeCategory.create!(category_scheme: @scheme, name: "Dining")
    @new_category = Myfin::SchemeCategory.create!(category_scheme: @scheme, name: "Coffee")
  end

  test "returns an entry's accessible changes newest first with render associations preloaded" do
    entry = create_entry(@accessible_account, "Accessible entry")
    older = create_change(entry:, created_at: 2.hours.ago)
    newer = create_change(entry:, created_at: 1.hour.ago)
    create_change(entry: create_entry(@inaccessible_account, "Private entry"), created_at: Time.current)

    changes = Myfin::ClassificationHistory.for_entry(user: @user, entry:).load

    assert_equal [ newer.id, older.id ], changes.map(&:id)
    changes.each do |change|
      assert_predicate change.association(:actor), :loaded?
      assert_predicate change.association(:category_scheme), :loaded?
      assert_predicate change.association(:previous_category), :loaded?
      assert_predicate change.association(:new_category), :loaded?
      assert_predicate change.association(:reverted_change), :loaded?
    end
  end

  test "returns only accessible recent changes and uses a stable cursor pair" do
    entry = create_entry(@accessible_account, "Accessible entry")
    oldest = create_change(entry:, created_at: 3.hours.ago)
    middle = create_change(entry:, created_at: 2.hours.ago)
    newest = create_change(entry:, created_at: 1.hour.ago)
    create_change(entry: create_entry(@inaccessible_account, "Private entry"), created_at: Time.current)

    page = Myfin::ClassificationHistory.recent(user: @user, limit: 2).load
    following_page = Myfin::ClassificationHistory.recent(
      user: @user,
      cursor: [ page.last.created_at, page.last.id ],
      limit: 2
    ).load

    assert_equal [ newest.id, middle.id ], page.map(&:id)
    assert_equal [ oldest.id ], following_page.map(&:id)
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

    def create_change(entry:, created_at:)
      Myfin::ClassificationChange.create!(
        family: @family,
        sure_transaction: entry.transaction,
        category_scheme: @scheme,
        actor: users(:family_admin),
        previous_category: @previous_category,
        previous_category_name: @previous_category.name,
        new_category: @new_category,
        new_category_name: @new_category.name,
        action: "edit",
        source: "transaction_explorer",
        created_at: created_at
      )
    end
end
