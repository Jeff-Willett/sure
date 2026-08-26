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
      profile = user.family.myfin_reporting_profiles.find_by(name: "Everything")
      Myfin::TransactionExplorer::Report.call(user: user, filters: filters, profile: profile)
    end

    def self.filter_params(params)
      params.permit(
        :search,
        entity_ids: [],
        years: [],
        months: [],
        types: [],
        wdg_categories: [],
        jpw_categories: [],
        detail_category_ids: [],
        wdg_rollup_ids: [],
        include_tag_ids: [],
        exclude_tag_ids: []
      )
    end
  end
end
