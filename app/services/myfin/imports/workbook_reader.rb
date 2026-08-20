module Myfin
  module Imports
    class WorkbookReader
      ROW_LIMIT = 10_000
      FORMULA_ERROR = /\A#(?:REF!|DIV\/0!|VALUE!|NAME\?|N\/A|NUM!|NULL!)/i

      def initialize(file, workbook: nil)
        @file = file
        @workbook = workbook
      end

      private
        attr_reader :file

        def workbook
          @workbook ||= Roo::Spreadsheet.open(file, extension: :xlsx)
        end

        def require_sheet!(name)
          raise WorkbookError, "missing required sheet #{name}" unless workbook.sheets.include?(name)

          workbook.sheet(name)
        end

        def validate_header!(sheet, row_number, expected)
          actual = read_cells(sheet, row_number, expected.length).map { |value| value.to_s.strip }
          return if actual == expected

          raise WorkbookError, "unexpected header"
        end

        def validate_row_limit!(sheet, header_row)
          data_rows = [ sheet.last_row.to_i - header_row, 0 ].max
          raise WorkbookError, "workbook exceeds #{ROW_LIMIT.to_fs(:delimited)} row limit" if data_rows > ROW_LIMIT
        end

        def read_cells(sheet, row_number, column_count)
          (1..column_count).map { |column| sheet.cell(row_number, column) }
        end

        def blank_row?(values)
          values.all?(&:blank?)
        end

        def reject_formula_errors!(values)
          raise WorkbookError, "formula error in source row" if values.any? { |value| value.to_s.match?(FORMULA_ERROR) }
        end
    end
  end
end
