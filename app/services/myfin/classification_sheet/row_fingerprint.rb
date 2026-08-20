module Myfin
  module ClassificationSheet
    class RowFingerprint
      def self.call(entry)
        transaction = entry.entryable
        raise ArgumentError, "transaction entry is required" unless transaction.is_a?(Transaction)

        payload = [
          entry.account.family_id,
          transaction.id,
          entry.id,
          entry.account_id,
          entry.date.iso8601,
          BigDecimal(entry.amount.to_s).to_s("F"),
          entry.currency,
          entry.source,
          entry.external_id
        ]

        Digest::SHA256.hexdigest(JSON.generate(payload))
      end
    end
  end
end
