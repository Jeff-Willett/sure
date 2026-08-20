module Myfin
  class SourceRecord < ApplicationRecord
    self.table_name = "myfin_source_records"

    DECISIONS = %w[created matched skipped review].freeze
    FORBIDDEN_PAYLOAD_KEYS = %w[access_url token authorization password].freeze

    belongs_to :import_batch,
      class_name: "Myfin::ImportBatch",
      inverse_of: :source_records
    belongs_to :entry, optional: true
    has_many :review_items,
      class_name: "Myfin::ReviewItem",
      inverse_of: :source_record,
      dependent: :destroy

    validates :source_record_key, :row_fingerprint, presence: true
    validates :decision, inclusion: { in: DECISIONS }
    validates :match_confidence,
      numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 },
      allow_nil: true
    validate :payload_contains_no_credentials
    validate :entry_belongs_to_import_family

    private
      def payload_contains_no_credentials
        return unless forbidden_payload_key?(payload)

        errors.add(:payload, "contains a forbidden credential field")
      end

      def forbidden_payload_key?(value)
        case value
        when Hash
          value.any? do |key, child|
            FORBIDDEN_PAYLOAD_KEYS.include?(key.to_s.downcase) || forbidden_payload_key?(child)
          end
        when Array
          value.any? { |child| forbidden_payload_key?(child) }
        else
          false
        end
      end

      def entry_belongs_to_import_family
        return if entry.nil? || import_batch.nil? || entry.account.family_id == import_batch.family_id

        errors.add(:entry, "must belong to the import family")
      end
  end
end
