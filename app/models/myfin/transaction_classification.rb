module Myfin
  class TransactionClassification < ApplicationRecord
    self.table_name = "myfin_transaction_classifications"

    SOURCES = %w[imported manual rule model].freeze

    belongs_to :sure_transaction,
      class_name: "Transaction",
      foreign_key: :transaction_id,
      inverse_of: :myfin_classifications
    belongs_to :category_scheme,
      class_name: "Myfin::CategoryScheme",
      inverse_of: :transaction_classifications
    belongs_to :scheme_category,
      class_name: "Myfin::SchemeCategory",
      inverse_of: :transaction_classifications
    belongs_to :reviewed_by, class_name: "User", optional: true

    has_many :classification_changes,
      ->(classification) { where(category_scheme_id: classification.category_scheme_id) },
      class_name: "Myfin::ClassificationChange",
      foreign_key: :transaction_id,
      primary_key: :transaction_id,
      inverse_of: false

    validates :classification_source, inclusion: { in: SOURCES }
    validates :confidence,
      numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 },
      allow_nil: true
    validates :transaction_id, uniqueness: { scope: :category_scheme_id }
    validate :scheme_category_belongs_to_declared_scheme
    validate :category_scheme_belongs_to_transaction_family
    validate :reviewer_belongs_to_transaction_family

    private
      def transaction_family_id
        sure_transaction&.entry&.account&.family_id
      end

      def scheme_category_belongs_to_declared_scheme
        return if scheme_category.nil? || scheme_category.category_scheme_id == category_scheme_id

        errors.add(:scheme_category, "must belong to the declared category scheme")
      end

      def category_scheme_belongs_to_transaction_family
        return if category_scheme.nil? || transaction_family_id.nil? || category_scheme.family_id == transaction_family_id

        errors.add(:category_scheme, "must belong to the transaction family")
      end

      def reviewer_belongs_to_transaction_family
        return if reviewed_by.nil? || transaction_family_id.nil? || reviewed_by.family_id == transaction_family_id

        errors.add(:reviewed_by, "must belong to the transaction family")
      end
  end
end
