module Myfin
  class ReportingProfileEntity < ApplicationRecord
    self.table_name = "myfin_reporting_profile_entities"

    belongs_to :reporting_profile,
      class_name: "Myfin::ReportingProfile",
      inverse_of: :reporting_profile_entities
    belongs_to :entity,
      class_name: "Myfin::Entity",
      inverse_of: :reporting_profile_entities

    validates :entity_id, uniqueness: { scope: :reporting_profile_id }
    validate :entity_belongs_to_reporting_profile_family

    private
      def entity_belongs_to_reporting_profile_family
        return if reporting_profile.nil? || entity.nil? || reporting_profile.family_id == entity.family_id

        errors.add(:entity, "must belong to the reporting profile family")
      end
  end
end
