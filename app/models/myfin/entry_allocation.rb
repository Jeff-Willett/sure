module Myfin
  class AllocationTotalError < StandardError; end

  class EntryAllocation < ApplicationRecord
    self.table_name = "myfin_entry_allocations"

    SOURCES = %w[account_default manual rule import].freeze

    belongs_to :entry
    belongs_to :entity, class_name: "Myfin::Entity", inverse_of: :entry_allocations

    validates :amount, numericality: true
    validates :allocation_source, inclusion: { in: SOURCES }
    validate :entity_belongs_to_entry_family

    def self.replace_for!(entry, allocations)
      attributes = allocations.map do |allocation|
        {
          entity: allocation.entity,
          amount: BigDecimal(allocation.amount.to_s),
          allocation_source: allocation.allocation_source
        }
      end
      total = attributes.sum(BigDecimal("0")) { |allocation| allocation.fetch(:amount) }

      unless total == BigDecimal(entry.amount.to_s)
        raise AllocationTotalError,
          "allocation total #{total.to_s("F")} does not equal entry amount #{entry.amount.to_d.to_s("F")}"
      end

      transaction do
        entry.lock!
        where(entry: entry).delete_all
        attributes.each { |allocation| create!(entry: entry, **allocation) }
      end

      where(entry: entry).reload
    end

    private
      def entity_belongs_to_entry_family
        return if entry.nil? || entity.nil? || entry.account.family_id == entity.family_id

        errors.add(:entity, "must belong to the entry family")
      end
  end
end
