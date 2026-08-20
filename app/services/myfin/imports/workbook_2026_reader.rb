module Myfin
  module Imports
    class Workbook2026Reader < WorkbookReader
      include Enumerable

      SHEET_NAMES = [
        "Chase Business Chk •2286",
        "Chase Ultimate •2788",
        "Chase Savings •5387",
        "Chase Total Chk •6626",
        "Chase Marriott •8188",
        "Chase Ultimate •8501",
        "Chase Prime Visa •8748"
      ].freeze
      HEADERS = [
        "Date",
        "Posted Date/Time",
        "Transaction Name",
        "Merchant",
        "Amount",
        "Currency",
        "Pending",
        "Channel",
        "Primary Category",
        "Detailed Category",
        "Transaction ID",
        "Account ID",
        "Account Name"
      ].freeze

      def self.call(file:)
        new(file).to_a
      end

      def each
        return enum_for(:each) unless block_given?

        transaction_ids = Set.new
        SHEET_NAMES.each do |sheet_name|
          sheet = require_sheet!(sheet_name)
          validate_header!(sheet, 1, HEADERS)
          validate_row_limit!(sheet, 1)

          (2..sheet.last_row.to_i).each do |row_number|
            values = read_cells(sheet, row_number, HEADERS.length)
            next if blank_row?(values)

            reject_formula_errors!(values)
            row = build_row(sheet_name, row_number, values)
            unless transaction_ids.add?(row.provider_transaction_id)
              raise WorkbookError, "duplicate source transaction ID"
            end

            yield row
          end
        end
      end

      private
        def build_row(sheet_name, row_number, values)
          Row.from_2026_consolidated(
            sheet: sheet_name,
            sheet_row: row_number,
            date: values[0],
            posted_at: values[1],
            name: values[2],
            merchant: values[3],
            amount: values[4],
            currency: values[5],
            pending: values[6],
            channel: values[7],
            primary_category: values[8],
            detailed_category: values[9],
            transaction_id: values[10],
            account_id: values[11],
            account_name: values[12]
          )
        end
    end
  end
end
