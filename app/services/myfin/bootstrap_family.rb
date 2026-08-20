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

    PROFILE_DEFINITIONS = {
      "My Personal Finances" => [ "JPW Personal" ],
      "Green Capital Investing" => [ "Green Capital Investing" ],
      "Donna" => [ "Donna" ],
      "Danielle" => [ "Danielle" ],
      "Combined Household" => [ "JPW Personal", "Donna", "Danielle" ],
      "Everything" => ENTITY_DEFINITIONS.keys
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
        %w[JPW WDG].each { |name| find_or_create_category_scheme!(name) }
        find_or_create_category_scheme!("Source Provider")

        default_scheme = family.myfin_category_schemes.find_by!(name: "WDG")
        family.myfin_category_schemes.where.not(id: default_scheme.id).update_all(is_default: false)
        default_scheme.update!(is_default: true)
      end

      def find_or_create_category_scheme!(name)
        scheme = family.myfin_category_schemes.find_or_initialize_by(name: name)
        @created_category_schemes += 1 if scheme.new_record?
        scheme.save!
      end

      def create_reporting_profiles!
        family.myfin_reporting_profiles.update_all(is_default: false)

        PROFILE_DEFINITIONS.each do |name, entity_names|
          profile = family.myfin_reporting_profiles.find_or_initialize_by(name: name)
          @created_reporting_profiles += 1 if profile.new_record?
          profile.preferred_category_scheme = preferred_scheme_for(name)
          profile.is_default = name == "My Personal Finances"
          profile.save!

          entity_names.each do |entity_name|
            entity = family.myfin_entities.find_by!(name: entity_name)
            profile.reporting_profile_entities.find_or_create_by!(entity: entity)
          end
        end
      end

      def preferred_scheme_for(profile_name)
        return unless [ "My Personal Finances", "Combined Household", "Everything" ].include?(profile_name)

        family.myfin_category_schemes.find_by!(name: "WDG")
      end
  end
end
