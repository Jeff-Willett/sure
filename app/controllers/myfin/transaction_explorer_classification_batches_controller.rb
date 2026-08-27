module Myfin
  class TransactionExplorerClassificationBatchesController < ApplicationController
    class InvalidBatch < StandardError; end

    MAX_EDITS = 500

    def update
      return head :not_acceptable unless request.format.turbo_stream?

      edits = resolved_edits
      raise InvalidBatch if edits.empty? || edits.size > MAX_EDITS

      results = Myfin::TransactionClassification.transaction do
        edits.map do |edit|
          ClassificationEditor.call(
            entry: edit.fetch(:entry),
            scheme: edit.fetch(:scheme),
            target_category: edit.fetch(:target_category),
            expected_category: edit.fetch(:expected_category),
            actor: Current.user,
            source: "transaction_explorer"
          )
        end
      end

      last_edit = edits.last
      @change = results.last.change
      @report = TransactionExplorersController.report_for(
        user: Current.user,
        params: params
      )
      @visible_rows = @report.rows.first(TransactionExplorersController::MAX_VISIBLE_ROWS)
      @entry_id = last_edit.fetch(:entry).id
      @scheme_name = last_edit.fetch(:scheme).name
      @focus_fallback_entry_id = @report.rows.find { |row| row.entry_id == @entry_id }&.entry_id || @report.rows.first&.entry_id
      flash.now[:notice] = t("myfin.transaction_classifications.updated")

      render template: "myfin/transaction_explorer_classifications/update"
    rescue ClassificationEditor::StaleClassification
      head :conflict
    rescue ClassificationEditor::NotAuthorized
      head :forbidden
    rescue InvalidBatch, ClassificationEditor::InvalidCategory
      head :unprocessable_entity
    end

    private
      def resolved_edits
        rows = params.permit(edits: [ :entry_id, :scheme_id, :category_id, :expected_category_id ])
          .fetch(:edits, [])
          .map(&:to_h)
        entry_ids = rows.map { |row| row.fetch("entry_id") }.uniq
        entries = Current.accessible_entries.transactions
          .where(id: entry_ids)
          .includes(account: :account_shares)
          .index_by { |entry| entry.id.to_s }
        raise InvalidBatch unless entries.size == entry_ids.size

        seen = Set.new
        rows.map do |row|
          entry = entries.fetch(row.fetch("entry_id").to_s)
          permission = entry.account.permission_for(Current.user)
          raise ClassificationEditor::NotAuthorized unless permission.in?([ :owner, :full_control, :read_write ])

          scheme = Current.family.myfin_category_schemes.find_by(id: row.fetch("scheme_id")) || raise(InvalidBatch)
          key = [ entry.id, scheme.id ]
          raise InvalidBatch unless seen.add?(key)

          {
            entry: entry,
            scheme: scheme,
            target_category: category_for(scheme, row["category_id"], active: true),
            expected_category: category_for(scheme, row["expected_category_id"])
          }
        end
      end

      def category_for(scheme, category_id, active: false)
        return if category_id.blank?

        categories = active ? scheme.scheme_categories.active : scheme.scheme_categories
        categories.find_by(id: category_id) || raise(InvalidBatch)
      end
  end
end
