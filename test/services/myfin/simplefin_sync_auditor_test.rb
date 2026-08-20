require "test_helper"

class MyfinSimplefinSyncAuditorTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)
    @account = accounts(:depository)
    @item = SimplefinItem.create!(
      family: @family,
      name: "SimpleFIN audit test",
      access_url: "https://example.com/private-access-value"
    )
    simplefin_account = @item.simplefin_accounts.create!(
      name: "Checking 6626",
      account_id: "provider-account-6626",
      currency: "USD",
      account_type: "checking",
      current_balance: 100
    )
    @account.update!(simplefin_account: simplefin_account)
    @sync = @item.syncs.create!(
      status: "completed",
      completed_at: Time.current,
      sync_stats: {
        "total_accounts" => 7,
        "linked_accounts" => 7,
        "unlinked_accounts" => 0,
        "tx_imported" => 12,
        "tx_updated" => 4,
        "tx_seen" => 16,
        "holdings_found" => 0,
        "total_errors" => 0,
        "window_start" => "2026-08-19T00:00:00Z",
        "window_end" => "2026-08-20T00:00:00Z",
        "errors" => [ { "message" => @item.access_url } ],
        "access_url" => @item.access_url
      }
    )
  end

  test "stores only approved sync counts and dates" do
    batch = Myfin::SimplefinSyncAuditor.call(simplefin_item: @item, sync: @sync)

    assert_equal "completed", batch.status
    assert_equal "simplefin", batch.source_kind
    assert_equal 7, batch.counts.fetch("total_accounts")
    assert_equal 16, batch.counts.fetch("tx_seen")
    assert_equal "2026-08-19T00:00:00Z", batch.counts.fetch("window_start")
    refute batch.counts.key?("errors")
    refute batch.counts.key?("access_url")

    persisted_audit = [ batch.attributes, batch.source_records.map(&:attributes) ].to_json
    refute_includes persisted_audit, @item.access_url
    refute_includes persisted_audit, "private-access-value"
  end

  test "creates review for an ambiguous pending replacement without editing transactions" do
    pending = create_simplefin_entry(
      external_id: "simplefin_pending-1",
      pending: true,
      date: Date.new(2026, 8, 18)
    )
    first = create_simplefin_entry(
      external_id: "simplefin_posted-1",
      pending: false,
      date: Date.new(2026, 8, 18)
    )
    second = create_simplefin_entry(
      external_id: "simplefin_posted-2",
      pending: false,
      date: Date.new(2026, 8, 18)
    )
    pending.update!(notes: "Keep this note", user_modified: true)
    original_attributes = pending.attributes.slice("amount", "date", "name", "notes", "user_modified", "excluded")

    batch = Myfin::SimplefinSyncAuditor.call(simplefin_item: @item, sync: @sync)

    source_record = batch.source_records.find_by!(source_record_key: "pending:#{pending.id}")
    assert_equal "review", source_record.decision
    review = source_record.review_items.find_by!(reason: "pending_replacement")
    assert_equal [ first.id, second.id ].sort, review.candidate_entry_ids.sort
    assert_equal original_attributes, pending.reload.attributes.slice(*original_attributes.keys)
    assert_equal 1, batch.counts.fetch("pending_replacement_reviews")
  end

  test "rerunning the same sync audit is idempotent" do
    pending = create_simplefin_entry(
      external_id: "simplefin_pending-1",
      pending: true,
      date: Date.new(2026, 8, 18)
    )
    2.times do |index|
      create_simplefin_entry(
        external_id: "simplefin_posted-#{index}",
        pending: false,
        date: Date.new(2026, 8, 18)
      )
    end

    first_batch = Myfin::SimplefinSyncAuditor.call(simplefin_item: @item, sync: @sync)

    assert_no_difference([ "Myfin::ImportBatch.count", "Myfin::SourceRecord.count", "Myfin::ReviewItem.count" ]) do
      second_batch = Myfin::SimplefinSyncAuditor.call(simplefin_item: @item, sync: @sync)
      assert_equal first_batch, second_batch
    end
    assert first_batch.source_records.exists?(source_record_key: "pending:#{pending.id}")
  end

  private
    def create_simplefin_entry(external_id:, pending:, date:)
      @account.entries.create!(
        entryable: Transaction.new(extra: { "simplefin" => { "pending" => pending } }),
        amount: BigDecimal("19.95"),
        currency: "USD",
        date: date,
        name: "Synthetic merchant",
        source: "simplefin",
        external_id: external_id
      )
    end
end
