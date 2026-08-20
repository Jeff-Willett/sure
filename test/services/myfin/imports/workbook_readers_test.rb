require "test_helper"

class MyfinImportsWorkbookReadersTest < ActiveSupport::TestCase
  FakeSheet = Data.define(:rows) do
    def last_row
      rows.length
    end

    def cell(row, column)
      rows.dig(row - 1, column - 1)
    end
  end

  FakeWorkbook = Data.define(:sheet_rows) do
    def sheets
      sheet_rows.keys
    end

    def sheet(name)
      FakeSheet.new(rows: sheet_rows.fetch(name))
    end
  end

  test "reads the exact 2025 table shape and sign convention" do
    rows = Myfin::Imports::Workbook2025Reader.call(file: fixture_path("2025_sample.xlsx"))

    assert_equal 1, rows.length
    row = rows.first
    assert_equal "2025_full_Table:3", row.source_key
    assert_equal Date.new(2025, 5, 14), row.reporting_date
    assert_equal BigDecimal("22"), row.amount
    assert_equal "Freedom", row.account_alias
    assert_equal "Gas & Fuel", row.source_categories.fetch("JPW")
    assert_equal "Auto & Transport (Auto)", row.source_categories.fetch("WDG")
  end

  test "reads all seven 2026 account tabs and preserves channel metadata" do
    rows = Myfin::Imports::Workbook2026Reader.call(file: fixture_path("2026_sample.xlsx"))

    assert_equal 7, rows.length
    assert_equal Myfin::Imports::Workbook2026Reader::SHEET_NAMES, rows.map(&:account_alias)
    assert_equal Date.new(2026, 1, 2), rows.first.reporting_date
    assert_equal BigDecimal("16.23"), rows.first.amount
    assert_equal "online", rows.first.raw_payload.fetch("channel")
    assert_equal "entertainment_tv_movies", rows.first.source_categories.fetch("Source Provider")
  end

  test "rejects an unexpected 2025 header" do
    workbook = FakeWorkbook.new(
      sheet_rows: {
        "2025_full_Table" => [ [], [ "Wrong" ] ]
      }
    )
    reader = Myfin::Imports::Workbook2025Reader.new("unused.xlsx", workbook: workbook)

    error = assert_raises(Myfin::Imports::WorkbookError) { reader.to_a }
    assert_equal "unexpected header", error.message
  end

  test "rejects a missing 2026 account tab" do
    sheet_rows = valid_2026_sheet_rows
    sheet_rows.delete("Chase Ultimate •8501")
    reader = Myfin::Imports::Workbook2026Reader.new(
      "unused.xlsx",
      workbook: FakeWorkbook.new(sheet_rows: sheet_rows)
    )

    error = assert_raises(Myfin::Imports::WorkbookError) { reader.to_a }
    assert_match(/missing required sheet/, error.message)
  end

  test "rejects duplicate transaction IDs across 2026 tabs" do
    sheet_rows = valid_2026_sheet_rows
    sheet_rows.values.each { |rows| rows[1][10] = "duplicate-id" }
    reader = Myfin::Imports::Workbook2026Reader.new(
      "unused.xlsx",
      workbook: FakeWorkbook.new(sheet_rows: sheet_rows)
    )

    error = assert_raises(Myfin::Imports::WorkbookError) { reader.to_a }
    assert_equal "duplicate source transaction ID", error.message
  end

  test "rejects a formula error" do
    sheet_rows = valid_2026_sheet_rows
    sheet_rows.values.first[1][4] = "#VALUE!"
    reader = Myfin::Imports::Workbook2026Reader.new(
      "unused.xlsx",
      workbook: FakeWorkbook.new(sheet_rows: sheet_rows)
    )

    error = assert_raises(Myfin::Imports::WorkbookError) { reader.to_a }
    assert_equal "formula error in source row", error.message
  end

  test "rejects more than ten thousand source rows" do
    workbook = FakeWorkbook.new(
      sheet_rows: {
        "2025_full_Table" => [ [], Myfin::Imports::Workbook2025Reader::HEADERS ] + Array.new(10_001) { [] }
      }
    )
    reader = Myfin::Imports::Workbook2025Reader.new("unused.xlsx", workbook: workbook)

    error = assert_raises(Myfin::Imports::WorkbookError) { reader.to_a }
    assert_match(/10,000 row limit/, error.message)
  end

  private
    def fixture_path(name)
      Rails.root.join("test/fixtures/files/myfin", name)
    end

    def valid_2026_sheet_rows
      Myfin::Imports::Workbook2026Reader::SHEET_NAMES.index_with do |sheet_name|
        suffix = sheet_name.last(4)
        [
          Myfin::Imports::Workbook2026Reader::HEADERS.dup,
          [
            "2026-01-01",
            "2026-01-02",
            "Synthetic purchase",
            "Synthetic Merchant",
            "16.23",
            "USD",
            false,
            "online",
            "entertainment",
            "entertainment_tv_movies",
            "transaction-#{suffix}",
            "account-#{suffix}",
            "TEST ACCOUNT"
          ]
        ]
      end
    end
end
