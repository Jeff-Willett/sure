require "test_helper"

class Myfin::SourceLineageTest < ViewComponent::TestCase
  setup do
    @entry = entries(:transaction)
    @batch = Myfin::ImportBatch.create!(
      family: @entry.account.family,
      source_kind: "google_sheet",
      source_locator: "private-sheet-id/2025_full_Table",
      source_fingerprint: "source-lineage-test"
    )
    @source_record = Myfin::SourceRecord.create!(
      import_batch: @batch,
      entry: @entry,
      source_record_key: "2025_full_Table:37",
      row_fingerprint: "lineage-row",
      payload: {},
      decision: "matched",
      match_method: "exact_details",
      match_confidence: 0.98
    )
  end

  test "shows only approved source history fields" do
    render_inline(Myfin::SourceLineage.new(entry: @entry))

    assert_text "Source history"
    assert_text "2025 WDG workbook"
    assert_text "2025_full_Table"
    assert_text "37"
    assert_text "Matched"
    assert_text "Exact details"
  end

  test "does not render credentials or raw provider identifiers from payloads" do
    @source_record.update_column(:payload, {
      "access_url" => "secret-access-url",
      "token" => "secret-token",
      "authorization" => "secret-authorization",
      "password" => "secret-password",
      "account_id" => "raw-account-id",
      "transaction_id" => "raw-transaction-id",
      "description" => "arbitrary-description"
    })

    render_inline(Myfin::SourceLineage.new(entry: @entry))

    assert_no_text "secret-access-url"
    assert_no_text "secret-token"
    assert_no_text "secret-authorization"
    assert_no_text "secret-password"
    assert_no_text "raw-account-id"
    assert_no_text "raw-transaction-id"
    assert_no_text "arbitrary-description"
  end
end
