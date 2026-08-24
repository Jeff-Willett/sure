module Myfin
  class ClassificationChange < ApplicationRecord
    self.table_name = "myfin_classification_changes"

    ACTIONS = %w[edit revert].freeze
    SOURCES = %w[transaction_explorer].freeze

    belongs_to :family
    belongs_to :sure_transaction,
      class_name: "Transaction",
      foreign_key: :transaction_id,
      inverse_of: :myfin_classification_changes
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
    validate :transaction_belongs_to_change_family
    validate :category_scheme_belongs_to_change_family
    validate :previous_category_belongs_to_declared_scheme
    validate :new_category_belongs_to_declared_scheme

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
        category_id = public_send(id_attribute)
        category_name = public_send(name_attribute)
        return if category_id.blank? && category_name.blank?

        if category_id.blank? || category_name.blank?
          errors.add(name_attribute, "must be present when the category is present")
          return
        end

        category = public_send(id_attribute.to_s.delete_suffix("_id"))
        return if category.nil? || category.name == category_name

        errors.add(name_attribute, "must match the category name")
      end

      def transaction_belongs_to_change_family
        return if sure_transaction.nil? || family_id.nil? || transaction_family_id == family_id

        errors.add(:transaction, "must belong to the change family")
      end

      def category_scheme_belongs_to_change_family
        return if category_scheme.nil? || family_id.nil? || category_scheme.family_id == family_id

        errors.add(:category_scheme, "must belong to the change family")
      end

      def previous_category_belongs_to_declared_scheme
        category_belongs_to_declared_scheme(:previous_category)
      end

      def new_category_belongs_to_declared_scheme
        category_belongs_to_declared_scheme(:new_category)
      end

      def category_belongs_to_declared_scheme(category_attribute)
        category = public_send(category_attribute)
        return if category.nil? || category_scheme_id.nil? || category.category_scheme_id == category_scheme_id

        errors.add(category_attribute, "must belong to the declared category scheme")
      end

      def transaction_family_id
        sure_transaction&.entry&.account&.family_id
      end

      def reject_mutation
        errors.add(:base, "classification changes are append-only")
        throw :abort
      end
  end
end
