module Myfin
  class TransactionExplorerCellBatchesController < ApplicationController
    class InvalidBatch < StandardError; end
    class StaleTags < StandardError; end

    MAX_EDITS = 500

    def update
      return head :not_acceptable unless request.format.json?

      edits = resolved_edits
      raise InvalidBatch if edits.empty? || edits.size > MAX_EDITS

      tag_entries = []
      Entry.transaction do
        edits.each do |edit|
          if edit.fetch(:field) == "detail_category"
            apply_category(edit)
          else
            apply_tags(edit)
            tag_entries << edit.fetch(:entry)
          end
        end
      end
      tag_entries.uniq.each(&:sync_account_later)

      report = TransactionExplorersController.report_for(
        user: Current.user,
        params: params
      )
      entry_ids = edits.map { |edit| edit.fetch(:entry).id }.to_set
      rows = report.working_rows.select { |row| entry_ids.include?(row.entry_id) }

      render json: {
        rows: view_context.transaction_explorer_tabulator_rows(rows)
      }
    rescue ClassificationEditor::StaleClassification, StaleTags
      head :conflict
    rescue ClassificationEditor::NotAuthorized
      head :forbidden
    rescue InvalidBatch, ClassificationEditor::InvalidCategory, KeyError
      head :unprocessable_entity
    end

    private
      def resolved_edits
        rows = params.permit(
          edits: [
            :field,
            :entry_id,
            :scheme_id,
            :category_id,
            :expected_category_id,
            { tag_ids: [], expected_tag_ids: [] }
          ]
        ).fetch(:edits, []).map(&:to_h)
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

          field = row.fetch("field")
          raise InvalidBatch unless %w[detail_category tags].include?(field)
          raise InvalidBatch unless seen.add?([ entry.id, field ])

          field == "detail_category" ? category_edit(entry, row) : tags_edit(entry, row)
        end
      end

      def category_edit(entry, row)
        scheme = Current.family.myfin_category_schemes.find_by(id: row.fetch("scheme_id")) || raise(InvalidBatch)
        {
          field: "detail_category",
          entry: entry,
          scheme: scheme,
          target_category: category_for(scheme, row["category_id"], active: true),
          expected_category: category_for(scheme, row["expected_category_id"])
        }
      end

      def tags_edit(entry, row)
        target_ids = normalized_tag_ids(row.fetch("tag_ids", []))
        expected_ids = Array(row.fetch("expected_tag_ids", [])).reject(&:blank?).map(&:to_s).uniq.sort
        {
          field: "tags",
          entry: entry,
          tag_ids: target_ids,
          expected_tag_ids: expected_ids
        }
      end

      def normalized_tag_ids(ids)
        submitted = Array(ids).reject(&:blank?).map(&:to_s).uniq.sort
        tags = Current.family.tags.where(id: submitted).to_a
        resolved = tags.map { |tag| tag.id.to_s }.sort
        hidden = tags.any? { |tag| tag.name.match?(TransactionExplorer::Report::LEGACY_CATEGORY_TAG) }
        raise InvalidBatch unless resolved == submitted && !hidden

        resolved
      end

      def category_for(scheme, category_id, active: false)
        return if category_id.blank?

        categories = active ? scheme.scheme_categories.active : scheme.scheme_categories
        categories.find_by(id: category_id) || raise(InvalidBatch)
      end

      def apply_category(edit)
        ClassificationEditor.call(
          entry: edit.fetch(:entry),
          scheme: edit.fetch(:scheme),
          target_category: edit.fetch(:target_category),
          expected_category: edit.fetch(:expected_category),
          actor: Current.user,
          source: "transaction_explorer"
        )
      end

      def apply_tags(edit)
        entry = edit.fetch(:entry)
        transaction = entry.transaction
        transaction.lock!
        current_tags = transaction.tags.to_a
        current_ids = current_tags
          .reject { |tag| tag.name.match?(TransactionExplorer::Report::LEGACY_CATEGORY_TAG) }
          .map { |tag| tag.id.to_s }
          .sort
        raise StaleTags unless current_ids == edit.fetch(:expected_tag_ids)

        hidden_ids = current_tags
          .select { |tag| tag.name.match?(TransactionExplorer::Report::LEGACY_CATEGORY_TAG) }
          .map(&:id)
        transaction.tag_ids = (hidden_ids + edit.fetch(:tag_ids)).uniq
        entry.lock_saved_attributes!
        entry.mark_user_modified!
        transaction.lock_attr!(:tag_ids)
      end
  end
end
