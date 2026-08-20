module Myfin
  module Imports
    class ReviewResolver
      class InvalidResolution < StandardError; end

      ACTIONS = %w[match_existing create_new skip dismiss_duplicate].freeze

      def self.call(review_item:, resolver:, action:, entry: nil, account: nil)
        new(review_item:, resolver:, action:, entry:, account:).call
      end

      def initialize(review_item:, resolver:, action:, entry: nil, account: nil)
        @review_item = review_item
        @resolver = resolver
        @action = action.to_s
        @entry = entry
        @account = account
      end

      def call
        raise InvalidResolution, "unsupported review action" unless ACTIONS.include?(action)

        review_item.with_lock do
          return review_item unless review_item.status == "open"

          validate_family!
          resolve!
        end

        review_item
      end

      private
        attr_reader :review_item, :resolver, :action, :entry, :account

        def source_record
          review_item.source_record
        end

        def batch
          source_record.import_batch
        end

        def validate_family!
          raise InvalidResolution, "resolver belongs to another family" unless resolver.family_id == review_item.family_id
          raise InvalidResolution, "source record belongs to another family" unless batch.family_id == review_item.family_id
        end

        def resolve!
          case action
          when "match_existing" then match_existing!
          when "create_new" then create_new!
          when "skip" then skip!
          when "dismiss_duplicate" then dismiss_duplicate!
          end
        end

        def match_existing!
          validate_entry!

          if review_item.reason == "pending_replacement"
            merge_pending_replacement!
          else
            write_with!(account: entry.account, reconciliation: reconciliation_for("matched", entry))
          end

          finish!(status: "resolved", note: "matched_existing")
        end

        def create_new!
          validate_account!
          write_with!(account: account, reconciliation: reconciliation_for("create", nil))
          finish!(status: "resolved", note: "created_new")
        end

        def skip!
          source_record.update!(decision: "skipped")
          finish!(status: "resolved", note: "skipped")
        end

        def dismiss_duplicate!
          source_record.entry&.transaction&.dismiss_duplicate_suggestion!
          source_record.update!(decision: "skipped")
          finish!(status: "dismissed", note: "dismissed_duplicate")
        end

        def validate_entry!
          unless entry&.entryable_type == "Transaction" && entry.account.family_id == review_item.family_id
            raise InvalidResolution, "candidate entry belongs to another family"
          end

          candidates = Array(review_item.candidate_entry_ids).map(&:to_s)
          if candidates.any? && !candidates.include?(entry.id.to_s)
            raise InvalidResolution, "entry is not a review candidate"
          end
        end

        def validate_account!
          unless account && account.family_id == review_item.family_id
            raise InvalidResolution, "account belongs to another family"
          end
        end

        def write_with!(account:, reconciliation:)
          Myfin::Imports::EntryWriter.call(
            batch: batch,
            account: account,
            row: normalized_row,
            reconciliation: reconciliation,
            source_record: source_record,
            force_create: reconciliation.decision == "create"
          )
        end

        def reconciliation_for(decision, candidate)
          Myfin::Imports::Reconciler::Result.new(
            decision: decision,
            entry: candidate,
            match_method: "manual_review",
            confidence: BigDecimal("1"),
            candidate_entry_ids: candidate ? [ candidate.id ] : []
          )
        end

        def normalized_row
          payload = source_record.payload.stringify_keys
          return normalized_2025_row(payload) if payload.key?("jpw_category")
          return normalized_2026_row(payload) if payload.key?("transaction_id")

          raise InvalidResolution, "this source row cannot be recreated automatically"
        end

        def normalized_2025_row(payload)
          Myfin::Imports::Row.from_2025_wdg(
            sheet_row: source_record.source_record_key.split(":").second,
            date: payload.fetch("date"),
            description: payload.fetch("description"),
            jpw_category: payload.fetch("jpw_category"),
            wdg_category: payload.fetch("wdg_category"),
            transaction_type: payload.fetch("transaction_type"),
            amount: payload.fetch("amount"),
            account: payload.fetch("account")
          )
        end

        def normalized_2026_row(payload)
          sheet, sheet_row, = source_record.source_record_key.split(":", 3)
          Myfin::Imports::Row.from_2026_consolidated(
            sheet: sheet,
            sheet_row: sheet_row,
            date: payload.fetch("date"),
            posted_at: payload["posted_at"],
            name: payload.fetch("name"),
            merchant: payload["merchant"],
            amount: payload.fetch("amount"),
            currency: payload.fetch("currency"),
            pending: payload["pending"],
            channel: payload["channel"],
            primary_category: payload["primary_category"],
            detailed_category: payload["detailed_category"],
            transaction_id: payload.fetch("transaction_id"),
            account_id: payload.fetch("account_id"),
            account_name: payload.fetch("account_name")
          )
        end

        def merge_pending_replacement!
          pending_entry = source_record.entry
          pending_transaction = pending_entry&.transaction
          unless pending_transaction&.pending? && pending_entry.account_id == entry.account_id
            raise InvalidResolution, "pending replacement is not eligible for this candidate"
          end

          pending_transaction.update!(
            extra: (pending_transaction.extra || {}).merge(
              "potential_posted_match" => {
                "entry_id" => entry.id,
                "reason" => "manual_review",
                "posted_amount" => entry.amount.to_s,
                "confidence" => "high",
                "detected_at" => Date.current.to_s
              }
            )
          )
          raise InvalidResolution, "pending replacement could not be merged" unless pending_transaction.merge_with_duplicate!

          source_record.update!(entry: entry, decision: "matched", match_method: "manual_review", match_confidence: 1)
        end

        def finish!(status:, note:)
          review_item.update!(
            status: status,
            resolved_by: resolver,
            resolved_at: Time.current,
            resolution_note: note
          )
        end
    end
  end
end
