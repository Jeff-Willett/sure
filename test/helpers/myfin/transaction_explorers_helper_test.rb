require "test_helper"

class MyfinTransactionExplorersHelperTest < ActionView::TestCase
  test "returns a relevant emoji for known rollup labels and a neutral fallback" do
    assert defined?(Myfin::TransactionExplorersHelper), "expected the Transaction Explorer helper to exist"

    helper = Object.new.extend(Myfin::TransactionExplorersHelper)

    assert_equal "🏕️", helper.transaction_explorer_rollup_emoji("Camping1")
    assert_equal "🛍️", helper.transaction_explorer_rollup_emoji("Shopping")
    assert_equal "🍽️", helper.transaction_explorer_rollup_emoji("Restaurants")
    assert_equal "🏠", helper.transaction_explorer_rollup_emoji("Renter Expenses")
    assert_equal "🚐", helper.transaction_explorer_rollup_emoji("Auto & Transport (RV)")
    assert_equal "💻", helper.transaction_explorer_rollup_emoji("GCI Business Software")
    assert_equal "🏷️", helper.transaction_explorer_rollup_emoji("A custom category")
  end
end
