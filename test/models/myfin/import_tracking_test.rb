require "test_helper"

class MyfinImportTrackingTest < ActiveSupport::TestCase
  test "one source record key is stored once per import batch" do
    family = families(:dylan_family)
    batch = Myfin::ImportBatch.create!(
      family: family,
      source_kind: "google_sheet",
      source_locator: "sheet/tab",
      source_fingerprint: "abc",
      status: "running"
    )
    attributes = {
      import_batch: batch,
      source_record_key: "row:3",
      row_fingerprint: "def",
      payload: { "amount" => "12.34" },
      decision: "review"
    }

    Myfin::SourceRecord.create!(attributes)

    assert_raises(ActiveRecord::RecordNotUnique) do
      Myfin::SourceRecord.create!(attributes)
    end
  end

  test "source records reject credential-shaped payload keys recursively" do
    batch = Myfin::ImportBatch.create!(
      family: families(:dylan_family),
      source_kind: "simplefin",
      source_locator: "simplefin/chase",
      source_fingerprint: "abc",
      status: "running"
    )
    record = Myfin::SourceRecord.new(
      import_batch: batch,
      source_record_key: "transaction:1",
      row_fingerprint: "def",
      payload: { "provider" => { "access_url" => "secret" } },
      decision: "review"
    )

    assert_not record.valid?
    assert_includes record.errors[:payload], "contains a forbidden credential field"
  end

  test "review items must stay inside the import family" do
    batch = Myfin::ImportBatch.create!(
      family: families(:dylan_family),
      source_kind: "google_sheet",
      source_locator: "sheet/tab",
      source_fingerprint: "abc",
      status: "running"
    )
    source_record = Myfin::SourceRecord.create!(
      import_batch: batch,
      source_record_key: "row:3",
      row_fingerprint: "def",
      payload: { "amount" => "12.34" },
      decision: "review"
    )
    other_family = Family.create!(name: "Other")
    review_item = Myfin::ReviewItem.new(
      family: other_family,
      source_record: source_record,
      reason: "ambiguous_match",
      status: "open"
    )

    assert_not review_item.valid?
    assert_includes review_item.errors[:source_record], "must belong to the review family"
  end
end
