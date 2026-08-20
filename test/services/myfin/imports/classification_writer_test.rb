require "test_helper"

class MyfinImportsClassificationWriterTest < ActiveSupport::TestCase
  test "writes one JPW and one WDG classification and mirrors WDG to Sure" do
    transaction = transactions(:one)
    Myfin::BootstrapFamily.call(family: transaction.entry.account.family)

    2.times do
      Myfin::Imports::ClassificationWriter.call(
        sure_transaction: transaction,
        classifications: {
          "JPW" => "Gas & Fuel",
          "WDG" => "Auto & Transport (Auto)"
        }
      )
    end

    assert_equal 2, transaction.myfin_classifications.reload.count
    assert_equal [ "JPW", "WDG" ],
      transaction.myfin_classifications
        .joins(:category_scheme)
        .order("myfin_category_schemes.name")
        .pluck("myfin_category_schemes.name")
    assert_equal "Auto & Transport (Auto)", transaction.reload.category.name
  end

  test "source provider classifications do not replace the Sure category" do
    transaction = transactions(:one)
    original_category = transaction.category
    Myfin::BootstrapFamily.call(family: transaction.entry.account.family)

    Myfin::Imports::ClassificationWriter.call(
      sure_transaction: transaction,
      classifications: { "Source Provider" => "shopping_online_marketplaces" }
    )

    assert_equal original_category, transaction.reload.category
    assert_equal "shopping_online_marketplaces",
      transaction.myfin_classifications.first.scheme_category.name
  end
end
