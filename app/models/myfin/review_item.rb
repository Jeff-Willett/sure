module Myfin
  class ReviewItem < ApplicationRecord
    self.table_name = "myfin_review_items"

    REASONS = %w[
      malformed_account
      duplicate_candidate
      ambiguous_match
      uncertain_category
      unknown_account
      invalid_row
      pending_replacement
    ].freeze
    STATUSES = %w[open resolved dismissed].freeze

    belongs_to :family
    belongs_to :source_record,
      class_name: "Myfin::SourceRecord",
      inverse_of: :review_items
    belongs_to :resolved_by, class_name: "User", optional: true

    validates :reason, inclusion: { in: REASONS }
    validates :status, inclusion: { in: STATUSES }
    validate :source_record_belongs_to_review_family
    validate :resolver_belongs_to_review_family

    private
      def source_record_belongs_to_review_family
        return if source_record.nil? || source_record.import_batch.family_id == family_id

        errors.add(:source_record, "must belong to the review family")
      end

      def resolver_belongs_to_review_family
        return if resolved_by.nil? || resolved_by.family_id == family_id

        errors.add(:resolved_by, "must belong to the review family")
      end
  end
end
