module Myfin
  class EntryAllocationsController < ApplicationController
    class InvalidAllocations < StandardError; end

    def update
      entry = Current.accessible_entries.transactions.find(params[:entry_id])
      return unless require_account_permission!(entry.account, :annotate, redirect_path: transaction_path(entry))

      allocations = build_allocations(entry)
      Myfin::EntryAllocation.replace_for!(entry, allocations)

      redirect_to transaction_path(entry), notice: t("myfin.entry_allocations.updated")
    rescue Myfin::AllocationTotalError, InvalidAllocations, ActiveRecord::RecordInvalid, ArgumentError => error
      render plain: t("myfin.entry_allocations.invalid", message: error.message), status: :unprocessable_entity
    end

    private
      def build_allocations(entry)
        rows = allocation_params
        entity_ids = rows.map { |row| row.fetch(:entity_id) }
        entities = Current.family.myfin_entities.active.where(id: entity_ids).index_by { |entity| entity.id.to_s }

        if entity_ids.any?(&:blank?) || entity_ids.uniq.length != entity_ids.length || entities.length != entity_ids.length
          raise InvalidAllocations, t("myfin.entry_allocations.invalid_entity")
        end

        rows.map do |row|
          Myfin::EntryAllocation.new(
            entry: entry,
            entity: entities.fetch(row.fetch(:entity_id)),
            amount: row.fetch(:amount),
            allocation_source: "manual"
          )
        end
      end

      def allocation_params
        params.permit(allocations: [ :entity_id, :amount ])
          .fetch(:allocations, [])
          .map { |row| row.to_h.symbolize_keys }
      end
  end
end
