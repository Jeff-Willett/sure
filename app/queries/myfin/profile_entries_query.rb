module Myfin
  class ProfileEntriesQuery
    class ProfileFamilyMismatch < StandardError; end

    def self.call(user:, profile:, relation: Entry.all)
      new(user:, profile:, relation:).call
    end

    def initialize(user:, profile:, relation:)
      @user = user
      @profile = profile
      @relation = relation
    end

    def call
      raise ProfileFamilyMismatch unless profile.family_id == user.family_id

      relation
        .joins(:myfin_allocations)
        .joins(<<~SQL.squish)
          INNER JOIN myfin_reporting_profile_entities
            ON myfin_reporting_profile_entities.entity_id = myfin_entry_allocations.entity_id
        SQL
        .where(myfin_reporting_profile_entities: { reporting_profile_id: profile.id })
        .where(account_id: user.accessible_accounts.select(:id))
        .distinct
    end

    private
      attr_reader :user, :profile, :relation
  end
end
