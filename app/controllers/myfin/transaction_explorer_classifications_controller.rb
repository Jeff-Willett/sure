module Myfin
  class TransactionExplorerClassificationsController < ApplicationController
    class InvalidClassification < StandardError; end

    def update
      return head :not_acceptable unless request.format.turbo_stream?

      entry = Current.accessible_entries.transactions.find_by!(id: params[:entry_id])
      return unless require_account_permission!(entry.account, :annotate)

      scheme = category_scheme
      result = ClassificationEditor.call(
        entry: entry,
        scheme: scheme,
        target_category: category_for(scheme, :category_id, active: true),
        expected_category: category_for(scheme, :expected_category_id),
        actor: Current.user,
        source: "transaction_explorer"
      )
      @change = result.change

      @report = TransactionExplorersController.report_for(user: Current.user, params: params)
      @visible_rows = @report.rows.first(TransactionExplorersController::MAX_VISIBLE_ROWS)
      @entry_id = entry.id
      @scheme_name = scheme.name
      @focus_fallback_entry_id = @report.rows.find { |row| row.entry_id == entry.id }&.entry_id || @report.rows.first&.entry_id
      flash.now[:notice] = t("myfin.transaction_classifications.updated")
    rescue ClassificationEditor::StaleClassification
      head :conflict
    rescue ClassificationEditor::NotAuthorized
      head :forbidden
    rescue InvalidClassification, ClassificationEditor::InvalidCategory
      head :unprocessable_entity
    end

    private
      def category_scheme
        Current.family.myfin_category_schemes.find_by(id: params[:scheme_id]) || raise(InvalidClassification)
      end

      def category_for(scheme, key, active: false)
        category_id = params[key]
        return if category_id.blank?

        categories = active ? scheme.scheme_categories.active : scheme.scheme_categories
        categories.find_by(id: category_id) || raise(InvalidClassification)
      end
  end
end
