module Myfin
  module Imports
    class BatchRunner
      Source = Data.define(:kind, :locator, :fingerprint)

      def self.call(family:, source:, rows:)
        new(family:, source:, rows:).call
      end

      def initialize(family:, source:, rows:)
        @family = family
        @source = source
        @rows = rows
      end

      def call
        validate_source!
        @batch = find_or_create_batch!
        return batch if batch.status == "completed"

        @claimed_entry_ids = batch.source_records
          .where(decision: %w[created matched])
          .where.not(entry_id: nil)
          .pluck(:entry_id)

        batch.update!(status: "running", started_at: batch.started_at || Time.current, error_summary: nil)
        rows.each { |row| process_row!(row) }
        batch.update!(status: "completed", completed_at: Time.current)
        batch
      rescue StandardError => error
        fail_batch!(error)
        raise
      end

      private
        attr_reader :family, :source, :rows, :batch, :claimed_entry_ids

        def find_or_create_batch!
          family.myfin_import_batches.find_or_create_by!(
            source_kind: source.kind,
            source_locator: source.locator,
            source_fingerprint: source.fingerprint
          )
        end

        def process_row!(row)
          if batch.source_records.exists?(source_record_key: row.source_key)
            increment_count!("skipped")
            return
          end

          account = AccountResolver.call(family: family, row: row)
          reconciliation = Reconciler.call(
            account: account,
            row: row,
            ignore_entry_ids: claimed_entry_ids
          )
          source_record = EntryWriter.call(
            batch: batch,
            account: account,
            row: row,
            reconciliation: reconciliation,
            force_create: reconciliation.decision == "create"
          )
          claimed_entry_ids << source_record.entry_id if source_record.entry_id.present?
          increment_count!(source_record.decision)
        rescue UnknownAccount
          write_account_review!(row, "unknown_account")
        rescue AmbiguousAccount
          write_account_review!(row, "ambiguous_match")
        end

        def write_account_review!(row, reason)
          Myfin::SourceRecord.transaction do
            source_record = batch.source_records.create!(
              source_record_key: row.source_key,
              row_fingerprint: RowFingerprint.call(row),
              payload: row.raw_payload,
              decision: "review",
              match_method: "account_resolver",
              match_confidence: 0
            )
            source_record.review_items.create!(
              family: family,
              reason: reason,
              candidate_entry_ids: []
            )
          end
          increment_count!("review")
        end

        def increment_count!(key)
          counts = batch.counts.deep_dup
          counts[key] = counts.fetch(key, 0).to_i + 1
          batch.update!(counts: counts)
        end

        def validate_source!
          raise ArgumentError, "invalid source kind" unless Myfin::ImportBatch::SOURCE_KINDS.include?(source.kind)
          raise ArgumentError, "source locator is required" if source.locator.blank?
          raise ArgumentError, "source fingerprint is required" if source.fingerprint.blank?
        end

        def fail_batch!(error)
          return if batch.nil? || batch.destroyed?

          batch.update_columns(
            status: "failed",
            error_summary: sanitized_error(error),
            completed_at: Time.current,
            updated_at: Time.current
          )
        end

        def sanitized_error(error)
          message = error.message.to_s
            .gsub(%r{https?://\S+}i, "[FILTERED_URL]")
            .gsub(/\b(access_url|authorization|password|token)\s*[=:]\s*\S+/i, "\\1=[FILTERED]")
          "#{error.class.name}: #{message}".truncate(500)
        end
    end
  end
end
