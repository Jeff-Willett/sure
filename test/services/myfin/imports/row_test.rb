require "test_helper"

class MyfinImportsRowTest < ActiveSupport::TestCase
  test "2025 banking signs become Sure signs" do
    row = Myfin::Imports::Row.from_2025_wdg(
      sheet_row: 3,
      date: "5/14/2025",
      description: "TAKE 5 CAR WASH",
      jpw_category: "Auto & Transport (Auto)",
      wdg_category: "Auto & Transport (Auto)",
      transaction_type: "Sale",
      amount: "-$22.00",
      account: "Freedom"
    )

    assert_equal BigDecimal("22.00"), row.amount
    assert_equal "2025_full_Table:3", row.source_key
    assert_equal Date.new(2025, 5, 14), row.reporting_date
    assert_equal({ "JPW" => "Auto & Transport (Auto)", "WDG" => "Auto & Transport (Auto)" }, row.source_categories)
  end

  test "2026 purchase sign and posted date are retained" do
    row = Myfin::Imports::Row.from_2026_consolidated(
      sheet: "Chase Ultimate •2788",
      sheet_row: 2,
      date: "2025-12-31",
      posted_at: "2026-01-01T14:50:50Z",
      name: "Hulu",
      merchant: "Hulu",
      amount: "$16.23",
      currency: "USD",
      pending: "FALSE",
      primary_category: "entertainment",
      detailed_category: "entertainment_tv_movies",
      transaction_id: "provider-1",
      account_id: "account-1",
      account_name: "CREDIT CARD"
    )

    assert_equal BigDecimal("16.23"), row.amount
    assert_equal Date.new(2025, 12, 31), row.transaction_date
    assert_equal Date.new(2026, 1, 1), row.reporting_date
    assert_not row.pending
    assert_equal "provider-1", row.provider_transaction_id
  end

  test "fingerprints are stable and change with financial identity" do
    first = build_2026_row(amount: "$16.23")
    same = build_2026_row(amount: "$16.23")
    changed = build_2026_row(amount: "$17.23")

    assert_equal Myfin::Imports::RowFingerprint.call(first), Myfin::Imports::RowFingerprint.call(same)
    assert_not_equal Myfin::Imports::RowFingerprint.call(first), Myfin::Imports::RowFingerprint.call(changed)
  end

  test "unsupported currencies fail before import" do
    assert_raises(Myfin::Imports::InvalidRow) do
      build_2026_row(currency: "CAD")
    end
  end

  private
    def build_2026_row(amount: "$16.23", currency: "USD")
      Myfin::Imports::Row.from_2026_consolidated(
        sheet: "Chase Ultimate •2788",
        sheet_row: 2,
        date: "2026-01-01",
        posted_at: "2026-01-02T14:50:50Z",
        name: "Hulu",
        merchant: "Hulu",
        amount: amount,
        currency: currency,
        pending: "FALSE",
        primary_category: "entertainment",
        detailed_category: "entertainment_tv_movies",
        transaction_id: "provider-1",
        account_id: "account-1",
        account_name: "CREDIT CARD"
      )
    end
end
