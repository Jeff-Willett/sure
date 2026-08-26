module Myfin
  class SchemeCategory < ApplicationRecord
    self.table_name = "myfin_scheme_categories"

    belongs_to :category_scheme,
      class_name: "Myfin::CategoryScheme",
      inverse_of: :scheme_categories
    belongs_to :parent,
      class_name: "Myfin::SchemeCategory",
      optional: true,
      inverse_of: :children

    has_many :children,
      class_name: "Myfin::SchemeCategory",
      foreign_key: :parent_id,
      inverse_of: :parent,
      dependent: :restrict_with_error
    has_many :transaction_classifications,
      class_name: "Myfin::TransactionClassification",
      inverse_of: :scheme_category,
      dependent: :restrict_with_error
    has_one :wdg_rollup_mapping,
      class_name: "Myfin::CategoryRollupMapping",
      foreign_key: :source_category_id,
      inverse_of: :source_category,
      dependent: :restrict_with_error
    has_one :wdg_rollup_category,
      through: :wdg_rollup_mapping,
      source: :target_category
    has_many :incoming_rollup_mappings,
      class_name: "Myfin::CategoryRollupMapping",
      foreign_key: :target_category_id,
      inverse_of: :target_category,
      dependent: :restrict_with_error
    has_many :previous_classification_changes,
      class_name: "Myfin::ClassificationChange",
      foreign_key: :previous_category_id,
      inverse_of: :previous_category
    has_many :new_classification_changes,
      class_name: "Myfin::ClassificationChange",
      foreign_key: :new_category_id,
      inverse_of: :new_category

    validates :name, presence: true, uniqueness: { scope: [ :category_scheme_id, :parent_id ] }
    validate :parent_belongs_to_category_scheme

    scope :active, -> { where(active: true) }

    private
      def parent_belongs_to_category_scheme
        return if parent.nil? || parent.category_scheme_id == category_scheme_id

        errors.add(:parent, "must belong to the category scheme")
      end
  end
end
