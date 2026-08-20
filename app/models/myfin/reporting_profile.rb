module Myfin
  class ReportingProfile < ApplicationRecord
    self.table_name = "myfin_reporting_profiles"

    belongs_to :family
    belongs_to :preferred_category_scheme,
      class_name: "Myfin::CategoryScheme",
      optional: true

    has_many :reporting_profile_entities,
      class_name: "Myfin::ReportingProfileEntity",
      inverse_of: :reporting_profile,
      dependent: :destroy
    has_many :entities, through: :reporting_profile_entities

    validates :name, presence: true, uniqueness: { scope: :family_id }
    validate :preferred_scheme_belongs_to_family

    private
      def preferred_scheme_belongs_to_family
        return if preferred_category_scheme.nil? || preferred_category_scheme.family_id == family_id

        errors.add(:preferred_category_scheme, "must belong to the reporting profile family")
      end
  end
end
