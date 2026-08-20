module Myfin
  class TransactionSemantics
    def self.label(entry)
      new(entry).label
    end

    def initialize(entry)
      @entry = entry
    end

    def label
      return "payment" if transaction.kind == "cc_payment"
      return "transfer" if transaction.kind == "funds_movement"
      return "neutral" if entry.amount.zero?

      if entry.account.accountable_type == "CreditCard"
        entry.amount.positive? ? "purchase" : "refund_or_credit"
      else
        entry.amount.positive? ? "expense" : "income"
      end
    end

    private
      attr_reader :entry

      def transaction
        entry.entryable
      end
  end
end
