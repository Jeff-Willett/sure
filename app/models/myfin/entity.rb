module Myfin
  class Entity < ApplicationRecord
    self.table_name = "myfin_entities"

    ENTITY_TYPES = %w[person business household other].freeze

    belongs_to :family

    has_many :account_entities,
      class_name: "Myfin::AccountEntity",
      inverse_of: :entity,
      dependent: :destroy
    has_many :accounts, through: :account_entities
    has_many :entry_allocations,
      class_name: "Myfin::EntryAllocation",
      inverse_of: :entity,
      dependent: :restrict_with_error
    has_many :category_schemes,
      class_name: "Myfin::CategoryScheme",
      inverse_of: :entity,
      dependent: :nullify
    has_many :reporting_profile_entities,
      class_name: "Myfin::ReportingProfileEntity",
      inverse_of: :entity,
      dependent: :destroy
    has_many :reporting_profiles, through: :reporting_profile_entities

    validates :name, presence: true, uniqueness: { scope: :family_id }
    validates :entity_type, inclusion: { in: ENTITY_TYPES }

    scope :active, -> { where(active: true) }
  end
end
