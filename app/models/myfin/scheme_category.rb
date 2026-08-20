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
