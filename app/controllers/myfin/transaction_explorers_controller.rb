module Myfin
  class TransactionExplorersController < ApplicationController
    MAX_VISIBLE_ROWS = 250

    def show
      @report = self.class.report_for(user: Current.user, params: params)
      @visible_rows = @report.rows.first(MAX_VISIBLE_ROWS)
      @breadcrumbs = [
        [ t("breadcrumbs.home"), root_path ],
        [ t("myfin.transaction_explorer.title"), nil ]
      ]
    end

    def self.report_for(user:, params:)
      filters = Myfin::TransactionExplorer::Filters.from_params(filter_params(params))
      Myfin::TransactionExplorer::Report.call(user: user, filters: filters)
    end

    def self.filter_params(params)
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
