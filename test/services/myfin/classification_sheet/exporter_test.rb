require "test_helper"

class MyfinClassificationSheetExporterTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)
    Myfin::BootstrapFamily.call(family: @family)
  end

  test "exports one stable row per family transaction" do
    result = Myfin::ClassificationSheet::Exporter.call(family: @family)
    expected_ids = @family.entries.where(entryable_type: "Transaction").pluck(:entryable_id).sort
    exported_ids = result.fetch(:rows).map { |row| row.fetch("transaction_id") }

    assert_equal expected_ids, exported_ids.sort
    assert_equal exported_ids.uniq.count, exported_ids.count
    assert_equal exported_ids.count, result.fetch(:export).row_count
  end

  test "existing WDG and JPW values seed final columns" do
    entry = create_entry("Reviewed merchant")
    Myfin::Imports::ClassificationWriter.call(
      sure_transaction: entry.transaction,
      classifications: { "WDG" => "Shopping", "JPW" => "Restaurants" }
    )

    row = Myfin::ClassificationSheet::Exporter.call(family: @family).fetch(:rows)
      .find { |candidate| candidate.fetch("entry_id") == entry.id }

    assert_equal "Shopping", row.fetch("final_wdg_category")
    assert_equal "Restaurants", row.fetch("final_jpw_category")
    assert_equal "Existing approved", row.fetch("review_status")
    assert_predicate row.fetch("row_fingerprint"), :present?
  end

  private
    def create_entry(name)
      Account::ProviderImportAdapter.new(accounts(:credit_card)).import_transaction(
        external_id: "export_#{SecureRandom.hex(8)}",
        amount: 25,
        currency: "USD",
        date: Date.current,
        name: name,
        source: "simplefin"
      )
    end
end
