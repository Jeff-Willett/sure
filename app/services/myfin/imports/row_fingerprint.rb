require "digest"
require "json"

module Myfin
  module Imports
    class RowFingerprint
      def self.call(row)
        canonical = {
          source_key: row.source_key,
          account_alias: row.account_alias,
          reporting_date: row.reporting_date.iso8601,
          amount: row.amount.to_s("F"),
          name: normalize_name(row.name),
          provider_transaction_id: row.provider_transaction_id
        }

        Digest::SHA256.hexdigest(JSON.generate(canonical))
      end

      def self.normalize_name(value)
        value.to_s
          .unicode_normalize(:nfkc)
          .downcase
          .gsub(/[^a-z0-9]+/, " ")
          .squish
      end
      private_class_method :normalize_name
    end
  end
end
