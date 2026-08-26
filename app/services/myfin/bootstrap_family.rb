module Myfin
  class BootstrapFamily
    Result = Data.define(
      :created_entities,
      :created_category_schemes,
      :created_reporting_profiles
    )

    ENTITY_DEFINITIONS = {
      "JPW Personal" => "person",
      "Green Capital Investing" => "business",
      "Donna" => "person",
      "Danielle" => "person"
    }.freeze

    CATEGORY_SCHEME_DEFINITIONS = {
      "JPW" => "JPW Personal",
      "DIS" => "Donna",
      "GCI" => "Green Capital Investing",
      "WDG" => nil,
      "Source Provider" => nil
    }.freeze

    PROFILE_DEFINITIONS = {
      "JPW Personal" => { entities: [ "JPW Personal" ], preferred_scheme: "JPW" },
      "WDG Report" => { entities: [ "JPW Personal" ], preferred_scheme: "WDG" },
      "Donna" => { entities: [ "Donna" ], preferred_scheme: "DIS" },
      "Green Capital Investing" => { entities: [ "Green Capital Investing" ], preferred_scheme: "GCI" },
      "Everything" => { entities: ENTITY_DEFINITIONS.keys, preferred_scheme: nil }
    }.freeze

    def self.call(family:)
      new(family).call
    end

    def initialize(family)
      @family = family
      @created_entities = 0
      @created_category_schemes = 0
      @created_reporting_profiles = 0
    end

    def call
      family.with_lock do
        create_entities!
        create_category_schemes!
        create_reporting_profiles!
      end

      Result.new(
        created_entities: created_entities,
        created_category_schemes: created_category_schemes,
        created_reporting_profiles: created_reporting_profiles
      )
    end

    private
      attr_reader :family,
        :created_entities,
        :created_category_schemes,
        :created_reporting_profiles

      def create_entities!
        ENTITY_DEFINITIONS.each do |name, entity_type|
          entity = family.myfin_entities.find_or_initialize_by(name: name)
          @created_entities += 1 if entity.new_record?
          entity.update!(entity_type: entity_type, active: true)
        end
      end

      def create_category_schemes!
        family.myfin_category_schemes.update_all(is_default: false)

        CATEGORY_SCHEME_DEFINITIONS.each do |name, entity_name|
          scheme = family.myfin_category_schemes.find_or_initialize_by(name: name)
          @created_category_schemes += 1 if scheme.new_record?
          scheme.update!(
            entity: entity_name ? family.myfin_entities.find_by!(name: entity_name) : nil,
            is_default: entity_name.present?
          )
        end
      end

      def create_reporting_profiles!
        rename_legacy_personal_profile!
        family.myfin_reporting_profiles.update_all(is_default: false)

        PROFILE_DEFINITIONS.each do |name, definition|
          profile = family.myfin_reporting_profiles.find_or_initialize_by(name: name)
          @created_reporting_profiles += 1 if profile.new_record?
          profile.preferred_category_scheme = definition.fetch(:preferred_scheme)&.then do |scheme_name|
            family.myfin_category_schemes.find_by!(name: scheme_name)
          end
          profile.is_default = name == "JPW Personal"
          profile.save!

          entity_ids = definition.fetch(:entities).map do |entity_name|
            entity = family.myfin_entities.find_by!(name: entity_name)
            profile.reporting_profile_entities.find_or_create_by!(entity: entity)
            entity.id
          end
          profile.reporting_profile_entities.where.not(entity_id: entity_ids).destroy_all
        end
      end

      def rename_legacy_personal_profile!
        return if family.myfin_reporting_profiles.exists?(name: "JPW Personal")

        family.myfin_reporting_profiles.find_by(name: "My Personal Finances")&.update!(name: "JPW Personal")
      end
  end
end
