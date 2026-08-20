module Myfin
  class DefaultAllocationBackfill
    class MissingDefaultEntity < StandardError; end

    def self.call(entry:)
      new(entry:).call
    end

    def initialize(entry:)
      @entry = entry
    end

    def call
      existing = entry.myfin_allocations.first
      return existing if existing

      owners = entry.account.myfin_account_entities
        .where(role: "owner", ownership_percent: 100)
        .where("starts_on IS NULL OR starts_on <= ?", entry.date)
        .where("ends_on IS NULL OR ends_on >= ?", entry.date)
        .to_a
      raise MissingDefaultEntity, "expected one default entity for account #{entry.account_id}" unless owners.one?

      EntryAllocation.create!(
        entry:,
        entity: owners.sole.entity,
        amount: entry.amount,
        allocation_source: "account_default"
      )
    end

    private
      attr_reader :entry
  end
end
