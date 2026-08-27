module Myfin
  class EntityCategoryContext
    Result = Data.define(
      :status,
      :entity,
      :scheme,
      :classification,
      :detail_category,
      :wdg_rollup
    )

    def self.call(entry:)
      new(entry).call
    end

    def initialize(entry)
      @entry = entry
    end

    def call
      allocations = entry.myfin_allocations.to_a
      return empty_result("needs_entity") if allocations.empty?
      return empty_result("split_allocation") unless allocations.one?

      entity = allocations.first.entity
      scheme = entity.category_schemes.find_by(is_default: true) || entity.category_schemes.first
      classification = entry.transaction.myfin_classifications.find do |candidate|
        candidate.category_scheme_id == scheme&.id
      end
      detail_category = classification&.scheme_category

      return Result.new(
        status: "needs_category",
        entity: entity,
        scheme: scheme,
        classification: nil,
        detail_category: nil,
        wdg_rollup: nil
      ) if detail_category.nil?

      wdg_rollup = detail_category.wdg_rollup_category
      status = scheme.name == "JPW" && wdg_rollup.nil? ? "needs_wdg_mapping" : "ready"

      Result.new(
        status: status,
        entity: entity,
        scheme: scheme,
        classification: classification,
        detail_category: detail_category,
        wdg_rollup: wdg_rollup
      )
    end

    private
      attr_reader :entry

      def empty_result(status)
        Result.new(
          status: status,
          entity: nil,
          scheme: nil,
          classification: nil,
          detail_category: nil,
          wdg_rollup: nil
        )
      end
  end
end
