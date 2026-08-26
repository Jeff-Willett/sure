module Myfin
  class CategoryRollupMapping < ApplicationRecord
    self.table_name = "myfin_category_rollup_mappings"

    belongs_to :source_category,
      class_name: "Myfin::SchemeCategory",
      inverse_of: :wdg_rollup_mapping
    belongs_to :target_category,
      class_name: "Myfin::SchemeCategory",
      inverse_of: :incoming_rollup_mappings

    validates :source_category_id, uniqueness: true
    validate :source_is_jpw
    validate :target_is_wdg
    validate :categories_share_family

    private
      def source_is_jpw
        return if source_category&.category_scheme&.name == "JPW"

        errors.add(:source_category, "must belong to the JPW scheme")
      end

      def target_is_wdg
        return if target_category&.category_scheme&.name == "WDG"

        errors.add(:target_category, "must belong to the WDG scheme")
      end

      def categories_share_family
        return if source_category.nil? || target_category.nil?
        return if source_category.category_scheme.family_id == target_category.category_scheme.family_id

        errors.add(:target_category, "must belong to the source category family")
      end
  end
end
