module Myfin
  class TransactionExplorersController < ApplicationController
    MAX_VISIBLE_ROWS = 250

    def show
      @result = Myfin::TransactionExplorerQuery.call(
        user: Current.user,
        filters: filter_params
      )
      @rows = @result.rows
      @visible_rows = @rows.first(MAX_VISIBLE_ROWS)
      @rollup_by_type = @result.rollup_rows.group_by(&:type)
      @filter_options = @result.filter_options
      @selected_filters = selected_filters
      @metrics = metrics
      @breadcrumbs = [
        [ t("breadcrumbs.home"), root_path ],
        [ t("myfin.transaction_explorer.title"), nil ]
      ]
    end

    private
      def filter_params
        params.permit(
          :search,
          entity_ids: [],
          years: [],
          months: [],
          types: [],
          wdg_categories: [],
          jpw_categories: []
        )
      end

      def selected_filters
        {
          entity_ids: selected_or_all(:entity_ids, @filter_options.entities.map(&:first)),
          years: selected_or_all(:years, @filter_options.years),
          months: selected_or_all(:months, @filter_options.months),
          types: selected_or_all(:types, @filter_options.types),
          wdg_categories: selected_or_all(:wdg_categories, @filter_options.wdg_categories),
          jpw_categories: selected_or_all(:jpw_categories, @filter_options.jpw_categories)
        }
      end

      def selected_or_all(key, available)
        requested = Array(params[key]).compact_blank.map(&:to_s)
        requested.presence || available.map(&:to_s)
      end

      def metrics
        {
          transactions: @rows.size,
          expenses: @rows.select { |row| row.type == "Expense" }.sum(BigDecimal("0")) { |row| row.amount.abs },
          income: @rows.select { |row| row.type == "Income" }.sum(BigDecimal("0"), &:amount),
          transfer_net: @rows.select { |row| row.type == "Transfer" }.sum(BigDecimal("0"), &:amount)
        }
      end
  end
end
