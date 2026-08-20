module Myfin
  class TransactionClassificationsController < ApplicationController
    class InvalidClassifications < StandardError; end

    def update
      entry = Current.accessible_entries.transactions.find_by!(entryable_id: params[:transaction_id])
      return unless require_account_permission!(entry.account, :annotate, redirect_path: transaction_path(entry))

      replace_classifications(entry.transaction)

      redirect_to transaction_path(entry), notice: t("myfin.transaction_classifications.updated")
    rescue InvalidClassifications, ActiveRecord::RecordInvalid => error
      render plain: t("myfin.transaction_classifications.invalid", message: error.message), status: :unprocessable_entity
    end

    private
      def replace_classifications(transaction)
        Myfin::TransactionClassification.transaction do
          transaction.lock!

          classification_params.each do |row|
            scheme = Current.family.myfin_category_schemes.find_by(id: row.fetch(:category_scheme_id))
            raise InvalidClassifications, t("myfin.transaction_classifications.invalid_scheme") unless scheme

            classification = transaction.myfin_classifications.find_or_initialize_by(category_scheme: scheme)
            category_id = row[:scheme_category_id]

            if category_id.blank?
              classification.destroy! if classification.persisted?
              next
            end

            category = scheme.scheme_categories.active.find_by(id: category_id)
            raise InvalidClassifications, t("myfin.transaction_classifications.invalid_category") unless category

            classification.update!(
              scheme_category: category,
              classification_source: "manual",
              confidence: 1,
              reviewed_at: Time.current,
              reviewed_by: Current.user
            )
          end
        end
      end

      def classification_params
        params.permit(classifications: [ :category_scheme_id, :scheme_category_id ])
          .fetch(:classifications, [])
          .map { |row| row.to_h.symbolize_keys }
      end
  end
end
