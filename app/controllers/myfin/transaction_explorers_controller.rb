module Myfin
  class TransactionExplorersController < ApplicationController
    MAX_VISIBLE_ROWS = 250

    def show
      filters = Myfin::TransactionExplorer::Filters.from_params(filter_params)
      @report = Myfin::TransactionExplorer::Report.call(user: Current.user, filters: filters)
      @visible_rows = @report.rows.first(MAX_VISIBLE_ROWS)
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
  end
end
