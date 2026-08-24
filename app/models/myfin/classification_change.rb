module Myfin
  class ClassificationChange < ApplicationRecord
    self.table_name = "myfin_classification_changes"

    ACTIONS = %w[edit revert].freeze
    SOURCES = %w[transaction_explorer].freeze

    belongs_to :family
    belongs_to :transaction, class_name: "Transaction"
    belongs_to :category_scheme,
      class_name: "Myfin::CategoryScheme",
      inverse_of: :classification_changes
    belongs_to :actor, class_name: "User", optional: true
    belongs_to :previous_category,
      class_name: "Myfin::SchemeCategory",
      optional: true,
      inverse_of: :previous_classification_changes
    belongs_to :new_category,
      class_name: "Myfin::SchemeCategory",
      optional: true,
      inverse_of: :new_classification_changes
    belongs_to :reverted_change,
      class_name: "Myfin::ClassificationChange",
      optional: true,
      inverse_of: :reverted_by_changes

    has_many :reverted_by_changes,
      class_name: "Myfin::ClassificationChange",
      foreign_key: :reverted_change_id,
      inverse_of: :reverted_change

    validates :action, inclusion: { in: ACTIONS }
    validates :source, inclusion: { in: SOURCES }
    validate :previous_snapshot_is_consistent
    validate :new_snapshot_is_consistent

    before_update :reject_mutation
    before_destroy :reject_mutation

    private
      def previous_snapshot_is_consistent
        snapshot_is_consistent?(:previous_category_id, :previous_category_name)
      end

      def new_snapshot_is_consistent
        snapshot_is_consistent?(:new_category_id, :new_category_name)
      end

      def snapshot_is_consistent?(id_attribute, name_attribute)
        return if public_send(id_attribute).present? == public_send(name_attribute).present?

        errors.add(name_attribute, "must be present when the category is present")
      end

      def reject_mutation
        errors.add(:base, "classification changes are append-only")
        throw :abort
      end
  end
end
