module Myfin
  class ClassificationChangesController < ApplicationController
    PAGE_SIZE = 50

    def index
      if params[:entry_id].present?
        @entry = Current.accessible_entries.transactions.find(params[:entry_id])
        @changes = ClassificationHistory.for_entry(user: Current.user, entry: @entry)
        render :show
      else
        @changes = ClassificationHistory.recent(user: Current.user, cursor: parsed_cursor, limit: PAGE_SIZE)
      end
    end

    def revert
      @change = ClassificationHistory.recent(user: Current.user, limit: nil).find(params[:id])
      entry = @change.sure_transaction.entry
      return head :forbidden unless entry.account.permission_for(Current.user).in?([ :owner, :full_control, :read_write ])

      ClassificationEditor.call(
        entry: entry,
        scheme: @change.category_scheme,
        target_category: nil,
        expected_category: nil,
        actor: Current.user,
        source: "transaction_explorer",
        revert_of: @change
      )

      head :ok
    rescue ClassificationEditor::StaleClassification, ClassificationEditor::InvalidRevert
      current_category = @change.sure_transaction.myfin_classifications
        .find_by(category_scheme: @change.category_scheme)&.scheme_category
      render json: {
        current_category: current_category&.name || I18n.t("myfin.transaction_explorer.category_uncategorized"),
        history_url: myfin_entry_classification_changes_path(@change.sure_transaction.entry)
      }, status: :conflict
    rescue ClassificationEditor::InvalidCategory
      head :unprocessable_entity
    end

    private
      def parsed_cursor
        value = params[:cursor].to_s
        return if value.blank?

        created_at, id = value.split(",", 2)
        return if created_at.blank? || id.blank?

        [ Time.iso8601(created_at), id ]
      rescue ArgumentError
        nil
      end
  end
end
