module Myfin
  module ClassificationSheet
    class ExportRow
      def self.call(entry:, export:, proposal:)
        new(entry:, export:, proposal:).call
      end

      def initialize(entry:, export:, proposal:)
        @entry = entry
        @export = export
        @proposal = proposal
      end

      def call
        current_wdg = classification("WDG")
        current_jpw = classification("JPW")
        approved = current_wdg.present? && current_jpw.present?

        {
          "export_batch_id" => export.batch_id,
          "transaction_id" => transaction.id,
          "entry_id" => entry.id,
          "row_fingerprint" => RowFingerprint.call(entry),
          "transaction_date" => entry.date.iso8601,
          "account" => entry.account.name,
          "account_suffix" => entry.account.name.to_s[/\d{4}(?=\D*\z)/],
          "financial_entity" => financial_entity,
          "merchant" => transaction.merchant&.name,
          "description" => entry.name,
          "amount" => BigDecimal(entry.amount.to_s).to_s("F"),
          "direction" => TransactionSemantics.label(entry),
          "pending" => transaction.pending?,
          "transaction_kind" => transaction.kind,
          "source" => entry.source,
          "source_provider_category" => classification("Source Provider"),
          "current_sure_category" => transaction.category&.name,
          "current_wdg_classification" => current_wdg,
          "current_jpw_classification" => current_jpw,
          "current_non_jpw_tags" => transaction.tags.reject { |tag| tag.name.start_with?("JPW:") }.map(&:name).sort.join(", "),
          "final_wdg_category" => current_wdg.presence || proposal.wdg,
          "final_jpw_category" => current_jpw.presence || proposal.jpw,
          "confidence" => approved ? "approved" : proposal.confidence,
          "proposal_evidence" => approved ? "Imported historical classification" : proposal.evidence,
          "review_status" => approved ? "Existing approved" : proposal.status,
          "reviewer_notes" => ""
        }
      end

      private
        attr_reader :entry, :export, :proposal

        def transaction
          entry.transaction
        end

        def classification(scheme_name)
          transaction.myfin_classifications.find { |item| item.category_scheme.name == scheme_name }&.scheme_category&.name
        end

        def financial_entity
          entry.myfin_allocations.first&.entity&.name ||
            entry.account.myfin_account_entities.find { |ownership| ownership.role == "owner" }&.entity&.name
        end
    end
  end
end
