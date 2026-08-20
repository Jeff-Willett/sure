require "test_helper"

class MyfinImportsReconcilerTest < ActiveSupport::TestCase
  setup do
    @account = accounts(:depository)
  end

  test "matches an existing external identity" do
    entry = create_entry(name: "Different display name", external_id: "provider-1")

    assert_read_only do
      result = Myfin::Imports::Reconciler.call(account: @account, row: build_row)

      assert_equal "matched", result.decision
      assert_equal entry, result.entry
      assert_equal "external_id", result.match_method
      assert_equal BigDecimal("1"), result.confidence
    end
  end

  test "matches exact amount date and normalized name" do
    entry = create_entry(name: "HULU")

    assert_read_only do
      result = Myfin::Imports::Reconciler.call(account: @account, row: build_row)

      assert_equal "matched", result.decision
      assert_equal entry, result.entry
      assert_equal BigDecimal("0.98"), result.confidence
    end
  end

  test "matches a unique merchant within three days" do
    entry = create_entry(name: "Hulu *1234", date: Date.new(2026, 1, 4))

    assert_read_only do
      result = Myfin::Imports::Reconciler.call(account: @account, row: build_row)

      assert_equal "matched", result.decision
      assert_equal entry, result.entry
      assert_equal BigDecimal("0.93"), result.confidence
    end
  end

  test "returns review when two candidates tie" do
    first = create_entry(name: "Hulu")
    second = create_entry(name: "HULU")

    assert_read_only do
      result = Myfin::Imports::Reconciler.call(account: @account, row: build_row)

      assert_equal "review", result.decision
      assert_nil result.entry
      assert_equal [ first.id, second.id ].sort, result.candidate_entry_ids.sort
    end
  end

  test "returns create when no candidate qualifies" do
    create_entry(name: "Hulu", date: Date.new(2026, 1, 10))

    assert_read_only do
      result = Myfin::Imports::Reconciler.call(account: @account, row: build_row)

      assert_equal "create", result.decision
      assert_nil result.entry
      assert_empty result.candidate_entry_ids
    end
  end

  test "matches a unique same date amount and currency when provider names differ" do
    candidate = create_entry(name: "Different merchant")

    assert_read_only do
      result = Myfin::Imports::Reconciler.call(account: @account, row: build_row)

      assert_equal "matched", result.decision
      assert_equal "exact_amount_date", result.match_method
      assert_equal BigDecimal("0.90"), result.confidence
      assert_equal candidate, result.entry
      assert_equal [ candidate.id ], result.candidate_entry_ids
    end
  end

  test "returns review when same date amount and currency has multiple candidates" do
    first = create_entry(name: "First merchant")
    second = create_entry(name: "Second merchant")

    assert_read_only do
      result = Myfin::Imports::Reconciler.call(account: @account, row: build_row)

      assert_equal "review", result.decision
      assert_equal "exact_amount_date", result.match_method
      assert_equal [ first.id, second.id ].sort, result.candidate_entry_ids.sort
    end
  end

  private
    def create_entry(name:, date: Date.new(2026, 1, 2), external_id: nil)
      @account.entries.create!(
        entryable: Transaction.new,
        amount: BigDecimal("16.23"),
        currency: "USD",
        date: date,
        name: name,
        source: external_id.present? ? "spreadsheet" : nil,
        external_id: external_id
      )
    end

    def build_row
      Myfin::Imports::Row.from_2026_consolidated(
        sheet: "Chase Ultimate •2788",
        sheet_row: 2,
        date: "2026-01-01",
        posted_at: "2026-01-02T14:50:50Z",
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
    end

    def assert_read_only(&block)
      assert_no_difference([ "Entry.count", "Transaction.count" ], &block)
    end
end
