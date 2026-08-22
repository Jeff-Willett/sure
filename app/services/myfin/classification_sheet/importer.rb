module Myfin
  module ClassificationSheet
    class Importer
      InvalidImport = Class.new(StandardError)
      Result = Data.define(
        :apply,
        :total_rows,
        :changed_rows,
        :wdg_changes,
        :jpw_changes,
        :skipped_rows,
        :dry_run_fingerprint,
        :errors
      )

      def self.call(family:, export:, rows:, apply: false, expected_dry_run_fingerprint: nil)
        new(family:, export:, rows:, apply:, expected_dry_run_fingerprint:).call
      end

      def initialize(family:, export:, rows:, apply:, expected_dry_run_fingerprint:)
        @family = family
        @export = export
        @rows = rows
        @apply = apply
        @expected_dry_run_fingerprint = expected_dry_run_fingerprint
      end

      def call
        changes, errors, skipped = validate_rows
        fingerprint = Digest::SHA256.hexdigest(JSON.generate(changes))
        raise InvalidImport, errors.join("; ") if errors.any?

        if apply
          verify_dry_run_fingerprint!(fingerprint)
          Family.transaction(requires_new: true) do
            changes.each { |change| apply_change!(change) }
            export.update!(dry_run_fingerprint: fingerprint, applied_at: Time.current)
          end
        else
          export.update!(dry_run_fingerprint: fingerprint)
        end

        Result.new(
          apply:,
          total_rows: rows.length,
          changed_rows: changes.count { |change| change.fetch("wdg_changed") || change.fetch("jpw_changed") },
          wdg_changes: changes.count { |change| change.fetch("wdg_changed") },
          jpw_changes: changes.count { |change| change.fetch("jpw_changed") },
          skipped_rows: skipped,
          dry_run_fingerprint: fingerprint,
          errors:
        )
      end

      private
        attr_reader :family, :export, :rows, :apply, :expected_dry_run_fingerprint

        def validate_rows
          errors = []
          skipped = 0
          seen_transaction_ids = Set.new
          changes = []

          rows.each_with_index do |row, index|
            if row.fetch("export_batch_id").to_s != export.batch_id.to_s
              errors << "row #{index + 2}: export batch mismatch"
              next
            end

            transaction_id = row.fetch("transaction_id").to_s
            if seen_transaction_ids.include?(transaction_id)
              errors << "row #{index + 2}: duplicate transaction id #{transaction_id}"
              next
            end
            seen_transaction_ids << transaction_id

            if row.fetch("review_status").to_s == "Exclude from import"
              skipped += 1
              next
            end

            transaction = family.transactions.find_by(id: transaction_id)
            unless transaction
              errors << "row #{index + 2}: transaction is not in this family"
              next
            end

            entry = transaction.entry
            if entry.id.to_s != row.fetch("entry_id").to_s
              errors << "row #{index + 2}: entry id mismatch"
              next
            end

            actual_fingerprint = RowFingerprint.call(entry)
            unless ActiveSupport::SecurityUtils.secure_compare(actual_fingerprint, row.fetch("row_fingerprint").to_s)
              errors << "row #{index + 2}: row fingerprint mismatch"
              next
            end

            wdg = row.fetch("final_wdg_category").to_s.strip
            jpw = row.fetch("final_jpw_category").to_s.strip
            if wdg.blank? || jpw.blank?
              errors << "row #{index + 2}: both final categories are required"
              next
            end

            current = current_categories(transaction)
            changes << {
              "transaction_id" => transaction.id.to_s,
              "entry_id" => entry.id.to_s,
              "wdg" => wdg,
              "jpw" => jpw,
              "wdg_changed" => current["WDG"] != wdg,
              "jpw_changed" => current["JPW"] != jpw
            }
          end

          [ changes.sort_by { |change| change.fetch("transaction_id") }, errors, skipped ]
        end

        def current_categories(transaction)
          transaction.myfin_classifications.includes(:category_scheme, :scheme_category).to_h do |classification|
            [ classification.category_scheme.name, classification.scheme_category.name ]
          end
        end

        def apply_change!(change)
          transaction = family.transactions.find(change.fetch("transaction_id"))
          Imports::ClassificationWriter.call(
            sure_transaction: transaction,
            classifications: { "WDG" => change.fetch("wdg"), "JPW" => change.fetch("jpw") }
          )
          JpwTagSync.call(transaction:, category_name: change.fetch("jpw"))
        end

        def verify_dry_run_fingerprint!(fingerprint)
          expected = expected_dry_run_fingerprint.to_s
          raise InvalidImport, "expected dry-run fingerprint is required" if expected.blank?
          raise InvalidImport, "dry-run fingerprint mismatch" unless expected == fingerprint
          raise InvalidImport, "export dry-run fingerprint mismatch" unless export.dry_run_fingerprint == fingerprint
        end
    end
  end
end
