module Myfin
  module Imports
    class Reconciler
      Result = Data.define(
        :decision,
        :entry,
        :match_method,
        :confidence,
        :candidate_entry_ids
      )

      MATCH_WINDOW = 3.days

      def self.call(account:, row:, ignore_entry_ids: [])
        new(account:, row:, ignore_entry_ids: ignore_entry_ids).call
      end

      def initialize(account:, row:, ignore_entry_ids: [])
        @account = account
        @row = row
        @ignore_entry_ids = Array(ignore_entry_ids).compact
      end

      def call
        match_external_identity ||
          match_exact_details ||
          match_exact_amount_and_date ||
          match_nearby_merchant ||
          review_weak_candidates ||
          create_result
      end

      private
        attr_reader :account, :row, :ignore_entry_ids

        def match_external_identity
          return if row.provider_transaction_id.blank?

          external_ids = [
            row.provider_transaction_id,
            "simplefin_#{row.provider_transaction_id}"
          ]

          resolve(
            transaction_entries.where(external_id: external_ids).to_a,
            method: "external_id",
            confidence: BigDecimal("1")
          )
        end

        def match_exact_details
          candidates = amount_and_currency_scope
            .where(date: row.reporting_date)
            .to_a
            .select { |entry| name_matches?(entry) }

          resolve(candidates, method: "exact_details", confidence: BigDecimal("0.98"))
        end

        def match_exact_amount_and_date
          candidates = amount_and_currency_scope
            .where(date: row.reporting_date)
            .to_a

          resolve(candidates, method: "exact_amount_date", confidence: BigDecimal("0.90"))
        end

        def match_nearby_merchant
          candidates = amount_and_currency_scope
            .where(date: (row.reporting_date - MATCH_WINDOW)..(row.reporting_date + MATCH_WINDOW))
            .to_a
            .select { |entry| name_matches?(entry) }

          resolve(candidates, method: "nearby_merchant", confidence: BigDecimal("0.93"))
        end

        def review_weak_candidates
          candidates = amount_and_currency_scope
            .where(date: (row.reporting_date - MATCH_WINDOW)..(row.reporting_date + MATCH_WINDOW))
            .to_a
          return if candidates.empty?

          Result.new(
            decision: "review",
            entry: nil,
            match_method: "weak_candidate",
            confidence: BigDecimal("0"),
            candidate_entry_ids: candidates.map(&:id)
          )
        end

        def amount_and_currency_scope
          transaction_entries.where(amount: row.amount, currency: row.currency)
        end

        def transaction_entries
          scope = account.entries.where(entryable_type: "Transaction")
          scope = scope.where.not(id: ignore_entry_ids) if ignore_entry_ids.any?
          scope
        end

        def name_matches?(entry)
          normalized_entry_name = NameNormalizer.call(entry.name)
          row_names.any? { |name| name == normalized_entry_name }
        end

        def row_names
          @row_names ||= [ row.name, row.merchant ]
            .filter_map { |value| NameNormalizer.call(value).presence }
            .uniq
        end

        def resolve(candidates, method:, confidence:)
          return if candidates.empty?

          if candidates.one?
            Result.new(
              decision: "matched",
              entry: candidates.first,
              match_method: method,
              confidence: confidence,
              candidate_entry_ids: [ candidates.first.id ]
            )
          else
            Result.new(
              decision: "review",
              entry: nil,
              match_method: method,
              confidence: confidence,
              candidate_entry_ids: candidates.map(&:id)
            )
          end
        end

        def create_result
          Result.new(
            decision: "create",
            entry: nil,
            match_method: nil,
            confidence: BigDecimal("0"),
            candidate_entry_ids: []
          )
        end
    end
  end
end
