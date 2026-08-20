require "test_helper"

class Myfin::ReviewItemsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in @user = users(:family_admin)
    @family = @user.family
    Myfin::BootstrapFamily.call(family: @family)
    @account = accounts(:depository)
    @entity = @family.myfin_entities.find_by!(name: "JPW Personal")
    @account.myfin_account_entities.create!(entity: @entity, role: "owner", ownership_percent: 100)
    @candidate = create_candidate
    @review_item = create_review_item(candidate_entry_ids: [ @candidate.id ])
  end

  test "lists only open review items from the current family" do
    other_batch = create_batch(family: families(:empty), fingerprint: "other")
    other_source = create_source_record(batch: other_batch, key: "other:1")
    Myfin::ReviewItem.create!(family: families(:empty), source_record: other_source, reason: "invalid_row")

    get myfin_review_items_path

    assert_response :success
    assert_select "a[href=?]", myfin_review_item_path(@review_item)
    assert_no_match(/TAKE 5 CAR WASH/, response.body)
    assert_no_match(/OTHER FAMILY MERCHANT/, response.body)
  end

  test "shows source detail and family-scoped candidates" do
    get myfin_review_item_path(@review_item)

    assert_response :success
    assert_match(/TAKE 5 CAR WASH/, response.body)
    assert_select "form[action^=?]", match_existing_myfin_review_item_path(@review_item)
    assert_select "form[action=?]", create_new_myfin_review_item_path(@review_item)
  end

  test "matches a source row to a candidate once" do
    2.times do
      patch match_existing_myfin_review_item_path(@review_item), params: { candidate_entry_id: @candidate.id }
      assert_redirected_to myfin_review_item_path(@review_item)
    end

    assert_equal "resolved", @review_item.reload.status
    assert_equal @candidate, @review_item.source_record.reload.entry
    assert_equal "matched", @review_item.source_record.decision
    assert_equal @user, @review_item.resolved_by
    assert @review_item.resolved_at.present?
    assert_equal 1, @candidate.myfin_allocations.reload.count
  end

  test "refuses a candidate outside the family" do
    other_entry = families(:empty).accounts.create!(
      owner: users(:empty),
      name: "Other account",
      balance: 0,
      currency: "USD",
      accountable: Depository.create!,
      status: "active"
    ).entries.create!(
      entryable: Transaction.new,
      date: Date.new(2025, 5, 14),
      amount: 22,
      currency: "USD",
      name: "OTHER FAMILY MERCHANT"
    )

    patch match_existing_myfin_review_item_path(@review_item), params: { candidate_entry_id: other_entry.id }

    assert_response :unprocessable_entity
    assert_equal "open", @review_item.reload.status
    assert_nil @review_item.source_record.reload.entry
  end

  test "creates one new entry when repeated" do
    @review_item.update!(candidate_entry_ids: [])

    assert_difference("Entry.count", 1) do
      patch create_new_myfin_review_item_path(@review_item), params: { account_id: @account.id }
    end
    assert_no_difference("Entry.count") do
      patch create_new_myfin_review_item_path(@review_item), params: { account_id: @account.id }
    end

    assert_equal "resolved", @review_item.reload.status
    assert_equal "created", @review_item.source_record.reload.decision
    assert @review_item.source_record.entry.present?
  end

  test "merges a reviewed pending replacement into the posted entry" do
    pending = @account.entries.create!(
      entryable: Transaction.new(extra: { "simplefin" => { "pending" => true } }),
      amount: BigDecimal("19.95"),
      currency: "USD",
      date: Date.new(2026, 8, 18),
      name: "Pending merchant",
      external_id: "simplefin_pending-review",
      source: "simplefin"
    )
    posted = @account.entries.create!(
      entryable: Transaction.new(extra: { "simplefin" => { "pending" => false } }),
      amount: BigDecimal("19.95"),
      currency: "USD",
      date: Date.new(2026, 8, 19),
      name: "Posted merchant",
      external_id: "simplefin_posted-review",
      source: "simplefin"
    )
    batch = create_batch(fingerprint: "pending-review")
    source = Myfin::SourceRecord.create!(
      import_batch: batch,
      entry: pending,
      source_record_key: "pending:#{pending.id}",
      row_fingerprint: Digest::SHA256.hexdigest(pending.id),
      payload: { "observed_on" => pending.date.iso8601, "candidate_count" => 1 },
      decision: "review",
      match_method: "pending_replacement"
    )
    review = Myfin::ReviewItem.create!(
      family: @family,
      source_record: source,
      reason: "pending_replacement",
      candidate_entry_ids: [ posted.id ]
    )

    assert_difference("Entry.count", -1) do
      patch match_existing_myfin_review_item_path(review), params: { candidate_entry_id: posted.id }
    end

    assert_equal "resolved", review.reload.status
    assert_equal posted, source.reload.entry
    assert_equal "matched", source.decision
    assert_not Entry.exists?(pending.id)
  end

  test "skip and dismiss are idempotent" do
    patch skip_myfin_review_item_path(@review_item)
    patch skip_myfin_review_item_path(@review_item)

    assert_equal "resolved", @review_item.reload.status
    assert_equal "skipped", @review_item.source_record.reload.decision

    dismissed = create_review_item(key: "2025_full_Table:4", reason: "duplicate_candidate")
    patch dismiss_duplicate_myfin_review_item_path(dismissed)
    patch dismiss_duplicate_myfin_review_item_path(dismissed)

    assert_equal "dismissed", dismissed.reload.status
    assert_equal "skipped", dismissed.source_record.reload.decision
  end

  private
    def create_review_item(key: "2025_full_Table:3", reason: "ambiguous_match", candidate_entry_ids: [])
      batch = create_batch
      source_record = create_source_record(batch: batch, key: key)
      Myfin::ReviewItem.create!(
        family: @family,
        source_record: source_record,
        reason: reason,
        candidate_entry_ids: candidate_entry_ids
      )
    end

    def create_batch(family: @family, fingerprint: SecureRandom.hex(8))
      Myfin::ImportBatch.create!(
        family: family,
        source_kind: "google_sheet",
        source_locator: "synthetic/2025_full_Table",
        source_fingerprint: fingerprint
      )
    end

    def create_source_record(batch:, key:)
      Myfin::SourceRecord.create!(
        import_batch: batch,
        source_record_key: key,
        row_fingerprint: Digest::SHA256.hexdigest(key),
        payload: {
          "date" => "5/14/2025",
          "description" => batch.family == @family ? "TAKE 5 CAR WASH" : "OTHER FAMILY MERCHANT",
          "jpw_category" => "Gas & Fuel",
          "wdg_category" => "Auto & Transport (Auto)",
          "transaction_type" => "Sale",
          "amount" => "-$22.00",
          "account" => "Freedom"
        },
        decision: "review",
        match_method: "exact_details",
        match_confidence: 0.98
      )
    end

    def create_candidate
      @account.entries.create!(
        entryable: Transaction.new,
        amount: BigDecimal("22.00"),
        currency: "USD",
        date: Date.new(2025, 5, 14),
        name: "TAKE 5 CAR WASH"
      )
    end
end
