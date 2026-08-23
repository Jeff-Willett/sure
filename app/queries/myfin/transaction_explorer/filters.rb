module Myfin
  module TransactionExplorer
    class Filters
      NONE_VALUE = "__none__"
      FILTER_KEYS = %i[entity_ids years months types wdg_categories jpw_categories].freeze
      INTEGER_KEYS = %i[years months].freeze

      def self.from_params(params)
        new(params.to_h.with_indifferent_access)
      end

      attr_reader :search

      def initialize(params)
        @explicit = FILTER_KEYS.index_with { |key| params.key?(key) }
        @values = FILTER_KEYS.index_with { |key| normalize(key, params[key]) }
        @search = params[:search].to_s.strip.downcase
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
          return values.map(&:to_i).uniq if INTEGER_KEYS.include?(key)

          values.map(&:to_s).uniq
        end
    end
  end
end
