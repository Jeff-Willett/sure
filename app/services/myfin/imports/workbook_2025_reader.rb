module Myfin
  module Imports
    class Workbook2025Reader < WorkbookReader
      include Enumerable

      SHEET_NAME = "2025_full_Table"
      HEADER_ROW = 2
      HEADERS = [
        "Column 1",
        "Description",
        "JPW Category",
        "WDG Category",
        "Type",
        "Amount",
        "Account"
      ].freeze

      def self.call(file:)
        new(file).to_a
      end

      def each
        return enum_for(:each) unless block_given?

        sheet = require_sheet!(SHEET_NAME)
        validate_header!(sheet, HEADER_ROW, HEADERS)
        validate_row_limit!(sheet, HEADER_ROW)

        ((HEADER_ROW + 1)..sheet.last_row.to_i).each do |row_number|
          values = read_cells(sheet, row_number, HEADERS.length)
          next if blank_row?(values)

          reject_formula_errors!(values)
          yield Row.from_2025_wdg(
            sheet_row: row_number,
            date: values[0],
            description: values[1],
            jpw_category: values[2],
            wdg_category: values[3],
            transaction_type: values[4],
            amount: values[5],
            account: values[6]
          )
        end
      end
    end
  end
end
