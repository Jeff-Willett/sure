module Myfin
  module ClassificationSheet
    class Exporter
      SCHEMA_VERSION = 1

      def self.call(family:)
        new(family:).call
      end

      def initialize(family:)
        @family = family
      end

      def call
        export = family.myfin_classification_exports.create!(
          batch_id: SecureRandom.uuid,
          exported_at: Time.current
        )
        index = TrainingIndex.build(family:)
        rows = transaction_entries.map do |entry|
          proposal = ProposalEngine.call(entry:, index:)
          ExportRow.call(entry:, export:, proposal:)
        end
        data_fingerprint = Digest::SHA256.hexdigest(JSON.generate(rows))
        export.update!(row_count: rows.length, data_fingerprint:)

        {
          schema_version: SCHEMA_VERSION,
          export:,
          rows:,
          category_lists: category_lists,
          summary: rows.group_by { |row| row.fetch("review_status") }.transform_values(&:count)
        }
      end

      private
        attr_reader :family

        def transaction_entries
          family.entries
            .where(entryable_type: "Transaction")
            .includes(
              :myfin_allocations,
              account: { myfin_account_entities: :entity },
              entryable: [ :category, :merchant, :tags, { myfin_classifications: [ :category_scheme, :scheme_category ] } ]
            )
            .order(:date, :account_id, :amount, :id)
            .to_a
        end

        def category_lists
          family.myfin_category_schemes.where(name: %w[WDG JPW]).includes(:scheme_categories).to_h do |scheme|
            [ scheme.name, scheme.scheme_categories.map(&:name).sort ]
          end
        end
    end
  end
end
