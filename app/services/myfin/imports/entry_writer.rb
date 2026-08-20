module Myfin
  module Imports
    class MissingAccountEntity < StandardError; end
    class InvalidOwnershipTotal < StandardError; end

    class EntryWriter
      def self.call(batch:, account:, row:, reconciliation:, source_record: nil, force_create: false)
        new(batch:, account:, row:, reconciliation:, source_record:, force_create:).call
      end

      def initialize(batch:, account:, row:, reconciliation:, source_record: nil, force_create: false)
        @batch = batch
        @account = account
        @row = row
        @reconciliation = reconciliation
        @source_record = source_record
        @force_create = force_create
      end

      def call
        Myfin::SourceRecord.transaction do
          case reconciliation.decision
          when "create"
            write_entry!
          when "matched"
            attach_to_match!
          when "review"
            write_review!
          else
            raise ArgumentError, "unsupported reconciliation decision"
          end
        end
      end

      private
        attr_reader :batch, :account, :row, :reconciliation, :source_record, :force_create

        def write_entry!
          entry = if force_create
            account.entries.create!(
              entryable: Transaction.new(extra: { "myfin" => { "pending" => row.pending } }),
              external_id: stable_external_id,
              amount: row.amount,
              currency: row.currency,
              date: row.reporting_date,
              name: row.name,
              source: import_source
            )
          else
            Account::ProviderImportAdapter.new(account).import_transaction(
              external_id: stable_external_id,
              amount: row.amount,
              currency: row.currency,
              date: row.reporting_date,
              name: row.name,
              source: import_source,
              extra: { "myfin" => { "pending" => row.pending } }
            )
          end

          ensure_default_allocation!(entry)
          ClassificationWriter.call(
            sure_transaction: entry.transaction,
            classifications: row.source_categories
          )
          create_source_record!(decision: "created", entry: entry)
        end

        def attach_to_match!
          entry = reconciliation.entry
          ensure_default_allocation!(entry)
          ClassificationWriter.call(
            sure_transaction: entry.transaction,
            classifications: row.source_categories,
            mirror_native: false
          )
          create_source_record!(decision: "matched", entry: entry)
        end

        def write_review!
          source_record = create_source_record!(decision: "review")
          source_record.review_items.create!(
            family: batch.family,
            reason: "ambiguous_match",
            candidate_entry_ids: reconciliation.candidate_entry_ids
          )
          source_record
        end

        def create_source_record!(decision:, entry: nil)
          attributes = {
            entry: entry,
            source_record_key: row.source_key,
            row_fingerprint: RowFingerprint.call(row),
            payload: row.raw_payload,
            decision: decision,
            match_method: reconciliation.match_method,
            match_confidence: reconciliation.confidence
          }

          if source_record
            raise ArgumentError, "source record belongs to another import batch" unless source_record.import_batch_id == batch.id

            source_record.update!(attributes)
            source_record
          else
            batch.source_records.create!(attributes)
          end
        end

        def ensure_default_allocation!(entry)
          return if entry.myfin_allocations.exists?

          links = active_account_entities(entry.date)
          raise MissingAccountEntity, "account has no entity assignment" if links.empty?

          ownership_total = links.sum(BigDecimal("0")) { |link| BigDecimal(link.ownership_percent.to_s) }
          unless ownership_total == BigDecimal("100")
            raise InvalidOwnershipTotal, "account ownership must total 100 percent"
          end

          remaining = BigDecimal(entry.amount.to_s)
          allocations = links.each_with_index.map do |link, index|
            amount = if index == links.length - 1
              remaining
            else
              (BigDecimal(entry.amount.to_s) * BigDecimal(link.ownership_percent.to_s) / 100).round(4)
            end
            remaining -= amount

            Myfin::EntryAllocation.new(
              entity: link.entity,
              amount: amount,
              allocation_source: "account_default"
            )
          end

          Myfin::EntryAllocation.replace_for!(entry, allocations)
        end

        def active_account_entities(date)
          account.myfin_account_entities
            .includes(:entity)
            .where("starts_on IS NULL OR starts_on <= ?", date)
            .where("ends_on IS NULL OR ends_on >= ?", date)
            .order(:created_at, :id)
            .to_a
        end

        def stable_external_id
          row.provider_transaction_id.presence || "myfin_#{RowFingerprint.call(row)}"
        end

        def import_source
          "myfin_sheet_#{Digest::SHA256.hexdigest(batch.source_locator).first(12)}"
        end
    end
  end
end
