module Myfin
  class SimplefinSyncAuditor
    COUNT_KEYS = %w[
      total_accounts
      linked_accounts
      unlinked_accounts
      tx_imported
      tx_updated
      tx_seen
      holdings_found
      total_errors
    ].freeze
    DATE_KEYS = %w[window_start window_end].freeze

    def self.call(simplefin_item:, sync:)
      new(simplefin_item:, sync:).call
    end

    def initialize(simplefin_item:, sync:)
      @simplefin_item = simplefin_item
      @sync = sync
    end

    def call
      raise ArgumentError, "completed SimpleFIN sync is required" unless sync&.completed?

      @batch = find_or_create_batch!
      return batch if batch.status == "completed"

      batch.update!(status: "running", started_at: batch.started_at || Time.current, error_summary: nil)
      counts = approved_sync_stats
      counts["pending_transactions_checked"] = 0
      counts["pending_strong_candidates"] = 0
      counts["pending_replacement_reviews"] = 0

      pending_entries.find_each do |pending_entry|
        counts["pending_transactions_checked"] += 1
        result = Imports::Reconciler.call(
          account: pending_entry.account,
          row: row_for(pending_entry),
          ignore_entry_ids: [ pending_entry.id ]
        )

        if result.decision == "matched"
          counts["pending_strong_candidates"] += 1
        elsif result.decision == "review"
          write_review!(pending_entry, result)
          counts["pending_replacement_reviews"] += 1
        end
      end

      counts["sync_completed_at"] = sync.completed_at&.iso8601
      batch.update!(
        status: "completed",
        counts: counts.compact,
        completed_at: Time.current
      )
      batch
    rescue StandardError => error
      fail_batch!(error)
      raise
    end

    private
      attr_reader :simplefin_item, :sync, :batch

      def find_or_create_batch!
        simplefin_item.family.myfin_import_batches.find_or_create_by!(
          source_kind: "simplefin",
          source_locator: "simplefin_item/#{simplefin_item.id}",
          source_fingerprint: Digest::SHA256.hexdigest("simplefin_sync/#{sync.id}")
        )
      end

      def approved_sync_stats
        stats = sync.sync_stats.to_h.stringify_keys
        COUNT_KEYS.index_with { |key| stats[key].to_i }
          .merge(DATE_KEYS.index_with { |key| stats[key].presence }.compact)
      end

      def pending_entries
        account_ids = simplefin_item.accounts.map(&:id)
        return Entry.none if account_ids.empty?

        Entry.where(account_id: account_ids).pending
      end

      def row_for(entry)
        Imports::Row.new(
          source_key: "simplefin_pending:#{entry.id}",
          source_locator: "simplefin_item/#{simplefin_item.id}",
          account_alias: entry.account.name,
          transaction_date: entry.date,
          posted_at: nil,
          reporting_date: entry.date,
          name: entry.name,
          merchant: nil,
          amount: BigDecimal(entry.amount.to_s),
          currency: entry.currency,
          pending: true,
          source_categories: {}.freeze,
          provider_transaction_id: entry.external_id.to_s.delete_prefix("simplefin_").presence,
          provider_account_id: nil,
          raw_payload: {}.freeze
        )
      end

      def write_review!(pending_entry, result)
        return if batch.source_records.exists?(source_record_key: "pending:#{pending_entry.id}")

        Myfin::SourceRecord.transaction do
          source_record = batch.source_records.create!(
            entry: pending_entry,
            source_record_key: "pending:#{pending_entry.id}",
            row_fingerprint: Imports::RowFingerprint.call(row_for(pending_entry)),
            payload: {
              "pending_entry_id" => pending_entry.id,
              "candidate_count" => result.candidate_entry_ids.length,
              "observed_on" => pending_entry.date.iso8601
            },
            decision: "review",
            match_method: result.match_method,
            match_confidence: result.confidence
          )
          source_record.review_items.create!(
            family: simplefin_item.family,
            reason: "pending_replacement",
            candidate_entry_ids: result.candidate_entry_ids
          )
        end
      end

      def fail_batch!(error)
        return if batch.nil? || batch.destroyed?

        batch.update_columns(
          status: "failed",
          error_summary: "#{error.class.name}: SimpleFIN audit failed",
          completed_at: Time.current,
          updated_at: Time.current
        )
      end
  end
end
