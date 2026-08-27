module Myfin
  module TransactionExplorer
    class Filters
      NONE_VALUE = "__none__"
      FILTER_KEYS = %i[
        entity_ids years months types wdg_categories jpw_categories
        detail_category_ids wdg_rollup_ids include_tag_ids exclude_tag_ids
      ].freeze
      INTEGER_KEYS = %i[years months].freeze
      LEGACY_ALL_TYPES = %w[Expense Income Transfer].freeze

      def self.from_params(params)
        new(params.to_h.with_indifferent_access)
      end

      attr_reader :search

      def initialize(params)
        @explicit = FILTER_KEYS.index_with { |key| params.key?(key) }.freeze
        @values = FILTER_KEYS.index_with { |key| normalize(key, params[key]) }.freeze
        @search = params[:search].to_s.strip.downcase.freeze
        freeze
      end

      def values_for(key)
        @values.fetch(key.to_sym)
      end

      def explicit?(key)
        @explicit.fetch(key.to_sym)
      end

      def selected_values(key, available:)
        return available.map(&:to_s) unless explicit?(key)

        values_for(key).map(&:to_s)
      end

      private
        def normalize(key, raw)
          values = Array(raw).compact_blank.reject { |value| value == NONE_VALUE }
          return values.map(&:to_i).uniq.freeze if INTEGER_KEYS.include?(key)

          if key == :types && (LEGACY_ALL_TYPES - values).empty?
            values << "Refund"
          end

          values.map(&:to_s).uniq.freeze
        end
    end
  end
end
