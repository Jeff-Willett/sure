module Myfin
  class CategoryScheme < ApplicationRecord
    self.table_name = "myfin_category_schemes"

    belongs_to :family
    belongs_to :entity, class_name: "Myfin::Entity", optional: true, inverse_of: :category_schemes

    has_many :scheme_categories,
      class_name: "Myfin::SchemeCategory",
      inverse_of: :category_scheme,
      dependent: :destroy
    has_many :transaction_classifications,
      class_name: "Myfin::TransactionClassification",
      inverse_of: :category_scheme,
      dependent: :restrict_with_error
    has_many :classification_changes,
      class_name: "Myfin::ClassificationChange",
      inverse_of: :category_scheme

    validates :name, presence: true, uniqueness: { scope: :family_id }
    validate :entity_belongs_to_family

    private
      def entity_belongs_to_family
        return if entity.nil? || family_id == entity.family_id

        errors.add(:entity, "must belong to the category scheme family")
      end
  end
end
