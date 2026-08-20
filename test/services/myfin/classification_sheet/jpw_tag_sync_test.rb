require "test_helper"

class MyfinClassificationSheetJpwTagSyncTest < ActiveSupport::TestCase
  test "replaces only the managed JPW tag and is idempotent" do
    transaction = transactions(:one)
    family = transaction.entry.account.family
    original_unmanaged_names = transaction.tags.reject { |tag| tag.name.start_with?("JPW:") }.map(&:name)
    unrelated = family.tags.create!(name: "Reimbursable")
    old_jpw = family.tags.create!(name: "JPW: Shopping")
    transaction.tags << unrelated << old_jpw

    2.times do
      Myfin::ClassificationSheet::JpwTagSync.call(transaction:, category_name: "Restaurants")
    end

    expected_names = (original_unmanaged_names + [ "JPW: Restaurants", "Reimbursable" ]).sort
    assert_equal expected_names, transaction.tags.reload.order(:name).pluck(:name)
  end
end
