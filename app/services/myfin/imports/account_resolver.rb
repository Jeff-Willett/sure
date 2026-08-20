module Myfin
  module Imports
    class AccountResolver
      SUFFIX_BY_ALIAS = {
        "Freedom" => "2788",
        "Checking Account" => "6626",
        "Marriott" => "8188",
        "Amazon" => "8748",
        "Chase Business Chk •2286" => "2286",
        "Chase Ultimate •2788" => "2788",
        "Chase Savings •5387" => "5387",
        "Chase Total Chk •6626" => "6626",
        "Chase Marriott •8188" => "8188",
        "Chase Ultimate •8501" => "8501",
        "Chase Prime Visa •8748" => "8748"
      }.freeze

      def self.call(family:, row:)
        new(family, row).call
      end

      def initialize(family, row)
        @family = family
        @row = row
      end

      def call
        exact_provider_account || account_for_alias!
      end

      private
        attr_reader :family, :row

        def exact_provider_account
          return if row.provider_account_id.blank?

          matches = SimplefinAccount
            .joins(:simplefin_item)
            .where(simplefin_items: { family_id: family.id })
            .where(account_id: row.provider_account_id)
            .filter_map(&:current_account)
            .uniq

          choose!(matches) if matches.any?
        end

        def account_for_alias!
          suffix = SUFFIX_BY_ALIAS[row.account_alias.to_s.strip]
          raise UnknownAccount, "unknown account alias" if suffix.nil?

          matches = family.accounts.includes(:simplefin_account).select do |account|
            account_names(account).any? { |name| suffix_match?(name, suffix) }
          end

          choose!(matches)
        end

        def choose!(matches)
          raise UnknownAccount, "no linked account matched" if matches.empty?
          raise AmbiguousAccount, "more than one linked account matched" if matches.many?

          matches.first
        end

        def account_names(account)
          [ account.name, account.simplefin_account&.name ].compact
        end

        def suffix_match?(name, suffix)
          name.to_s.match?(/(?:\A|\D)#{Regexp.escape(suffix)}(?:\D|\z)/)
        end
    end
  end
end
