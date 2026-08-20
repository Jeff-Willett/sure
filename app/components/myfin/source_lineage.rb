module Myfin
  class SourceLineage < ApplicationComponent
    HistoryItem = Data.define(:source_name, :tab, :row, :imported_at, :decision, :match_method)

    attr_reader :entry

    def initialize(entry:)
      @entry = entry
    end

    def history_items
      @history_items ||= entry.myfin_source_records
        .includes(:import_batch)
        .order(created_at: :desc)
        .map { |source_record| history_item(source_record) }
    end

    private
      def history_item(source_record)
        tab, row = safe_location(source_record)
        HistoryItem.new(
          source_name: safe_source_name(source_record),
          tab: tab,
          row: row,
          imported_at: source_record.created_at,
          decision: source_record.decision.humanize,
          match_method: source_record.match_method&.humanize
        )
      end

      def safe_source_name(source_record)
        batch = source_record.import_batch
        return "SimpleFIN" if batch.source_kind == "simplefin"
        return "2025 WDG workbook" if source_record.source_record_key.start_with?("2025_full_Table:")
        return "2026 consolidated workbook" if batch.source_kind == "google_sheet"

        batch.source_kind.humanize
      end

      def safe_location(source_record)
        return [ nil, nil ] unless source_record.import_batch.source_kind == "google_sheet"

        tab, row, = source_record.source_record_key.split(":", 3)
        [ tab, row.to_s.match?(/\A\d+\z/) ? row : nil ]
      end
  end
end
