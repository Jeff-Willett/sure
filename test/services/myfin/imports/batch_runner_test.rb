require "test_helper"

class MyfinImportsBatchRunnerTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)
    @account = accounts(:depository)
    Myfin::BootstrapFamily.call(family: @family)
    @entity = @family.myfin_entities.find_by!(name: "JPW Personal")
    @account.myfin_account_entities.create!(
      entity: @entity,
      role: "owner",
      ownership_percent: 100
    )
    Myfin::Imports::AccountResolver.stubs(:call).returns(@account)
  end

  test "rerunning one source creates no additional entries" do
    row = normalized_2025_row

    assert_difference("Entry.count", 1) { run_batch([ row ]) }
    assert_no_difference("Entry.count") { run_batch([ row ]) }

    source_record = Myfin::SourceRecord.find_by!(source_record_key: row.source_key)
    assert_equal "created", source_record.decision
    assert_equal 1, source_record.entry.myfin_allocations.count
    assert_equal @entity, source_record.entry.myfin_allocations.first.entity
    assert_equal 2, source_record.entry.transaction.myfin_classifications.count
  end

  test "distinct source rows with identical details create distinct entries" do
    rows = [ normalized_2025_row, normalized_2025_row(sheet_row: 4) ]

    assert_difference("Entry.count", 2) do
      batch = run_batch(rows, fingerprint: "identical-rows-v1")

      assert_equal({ "created" => 2 }, batch.counts)
      assert_equal 2, batch.source_records.where(decision: "created").distinct.count(:entry_id)
    end
  end

  test "an ambiguous match creates a review item without another entry" do
    first = create_candidate(name: "TAKE 5 CAR WASH")
    second = create_candidate(name: "take 5 car wash")

    assert_no_difference("Entry.count") do
      batch = run_batch([ normalized_2025_row ], fingerprint: "ambiguous-v1")

      source_record = batch.source_records.find_by!(source_record_key: "2025_full_Table:3")
      assert_equal "review", source_record.decision
      assert_nil source_record.entry
      review = source_record.review_items.find_by!(reason: "ambiguous_match")
      assert_equal [ first.id, second.id ].sort, review.candidate_entry_ids.sort
    end
  end

  test "a matched row adds lineage and classifications without changing entry fields" do
    entry = create_candidate(name: "TAKE 5 CAR WASH")
    entry.transaction.update!(category: categories(:food_and_drink))
    entry.update!(notes: "Keep this note", user_modified: true)
    original_attributes = entry.attributes.slice("amount", "date", "name", "notes", "user_modified")
    original_category_id = entry.transaction.category_id

    assert_no_difference("Entry.count") do
      batch = run_batch([ normalized_2025_row ], fingerprint: "matched-v1")
      source_record = batch.source_records.find_by!(source_record_key: "2025_full_Table:3")

      assert_equal "matched", source_record.decision
      assert_equal entry, source_record.entry
    end

    assert_equal original_attributes, entry.reload.attributes.slice(*original_attributes.keys)
    assert_equal original_category_id, entry.transaction.reload.category_id
    assert_equal 2, entry.transaction.myfin_classifications.count
    assert_equal 1, entry.myfin_allocations.count
  end

  test "a classification failure rolls back the complete row" do
    Myfin::Imports::ClassificationWriter.stubs(:call).raises(StandardError, "classification write failed")

    assert_no_difference(
      [ "Entry.count", "Myfin::EntryAllocation.count", "Myfin::TransactionClassification.count", "Myfin::SourceRecord.count" ]
    ) do
      assert_raises(StandardError) do
        run_batch([ normalized_2025_row ], fingerprint: "failure-v1")
      end
    end

    batch = Myfin::ImportBatch.find_by!(source_fingerprint: "failure-v1")
    assert_equal "failed", batch.status
    assert_match(/StandardError/, batch.error_summary)
    assert_match(/classification write failed/, batch.error_summary)
  end

  private
    def run_batch(rows, fingerprint: "workbook-v1")
      source = Myfin::Imports::BatchRunner::Source.new(
        kind: "google_sheet",
        locator: "synthetic/2025_full_Table",
        fingerprint: fingerprint
      )

      Myfin::Imports::BatchRunner.call(family: @family, source: source, rows: rows)
    end

    def normalized_2025_row(sheet_row: 3)
      Myfin::Imports::Row.from_2025_wdg(
        sheet_row: sheet_row,
        date: "5/14/2025",
        description: "TAKE 5 CAR WASH",
        jpw_category: "Gas & Fuel",
        wdg_category: "Auto & Transport (Auto)",
        transaction_type: "Sale",
        amount: "-$22.00",
        account: "Freedom"
      )
    end

    def create_candidate(name:)
      @account.entries.create!(
        entryable: Transaction.new,
        amount: BigDecimal("22.00"),
        currency: "USD",
        date: Date.new(2025, 5, 14),
        name: name
      )
    end
end
