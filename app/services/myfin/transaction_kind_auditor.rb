module Myfin
  class TransactionKindAuditor
    Result = Data.define(:entry_ids, :candidate_count, :repaired_count)

    def self.call(family:, apply: false)
      new(family:, apply:).call
    end

    def initialize(family:, apply: false)
      @family = family
      @apply = apply
    end

    def call
      entry_ids = candidates.pluck(:id)
      repaired_count = 0

      if apply && entry_ids.any?
        repaired_count = Transaction
          .joins(:entry)
          .where(entries: { id: entry_ids })
          .where(kind: "cc_payment", transfer_id: nil)
          .update_all(kind: "standard", updated_at: Time.current)
      end

      Result.new(entry_ids:, candidate_count: entry_ids.length, repaired_count:)
    end

    private
      attr_reader :family, :apply

      def candidates
        Entry
          .joins(:account)
          .joins("INNER JOIN transactions ON transactions.id = entries.entryable_id AND entries.entryable_type = 'Transaction'")
          .where(accounts: { family_id: family.id, accountable_type: "CreditCard" })
          .where("entries.amount < 0")
          .where(transactions: { kind: "cc_payment", transfer_id: nil })
          .where.not("entries.name ~* ?", "^(automatic payment|automatic credit card payment|credit card payment|automatic payment - thank)$")
      end
  end
end
