require "test_helper"

class MyfinClassificationSheetRowFingerprintTest < ActiveSupport::TestCase
  setup do
    @entry = Account::ProviderImportAdapter.new(accounts(:depository)).import_transaction(
      external_id: "fingerprint_#{SecureRandom.hex(6)}",
      amount: 42.15,
      currency: "USD",
      date: Date.current,
      name: "Fingerprint merchant",
      source: "simplefin"
    )
  end

  test "classification edits do not change the row fingerprint" do
    before = Myfin::ClassificationSheet::RowFingerprint.call(@entry)

    @entry.transaction.update!(category: categories(:food_and_drink))

    assert_equal before, Myfin::ClassificationSheet::RowFingerprint.call(@entry.reload)
  end

  test "amount changes invalidate the row fingerprint" do
    before = Myfin::ClassificationSheet::RowFingerprint.call(@entry)

    @entry.update!(amount: @entry.amount + 1)

    assert_not_equal before, Myfin::ClassificationSheet::RowFingerprint.call(@entry)
  end
end
