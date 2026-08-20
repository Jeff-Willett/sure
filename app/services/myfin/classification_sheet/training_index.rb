module Myfin
  module ClassificationSheet
    class TrainingIndex
      Example = Data.define(:wdg, :jpw)

      MERCHANT_ALIASES = {
        /\b(?:wal mart|walmart|wm supercenter)\b/ => "walmart",
        /\btarget\b/ => "target",
        /\bamazon\b/ => "amazon"
      }.freeze

      def self.build(family:, ignore_entry_ids: [])
        new.tap do |index|
          family.transactions.includes(:myfin_classifications, entry: :account).find_each do |transaction|
            entry = transaction.entry
            next if ignore_entry_ids.include?(entry.id)

            classifications = transaction.myfin_classifications.index_by { |item| item.category_scheme.name }
            wdg = classifications["WDG"]&.scheme_category&.name
            jpw = classifications["JPW"]&.scheme_category&.name
            next if wdg.blank? || jpw.blank?

            index.add(entry:, wdg:, jpw:)
          end
        end
      end

      def self.merchant_key(name)
        normalized = Imports::NameNormalizer.call(name)
        alias_name = MERCHANT_ALIASES.find { |pattern, _value| normalized.match?(pattern) }&.last
        return alias_name if alias_name

        normalized.split(" ").first(3).reject { |token| token.match?(/\A\d+\z/) }.join(" ")
      end

      def initialize
        @examples = Hash.new { |hash, key| hash[key] = [] }
      end

      def add(entry:, wdg:, jpw:)
        examples[key_for(entry)] << Example.new(wdg:, jpw:)
      end

      def examples_for(entry)
        examples.fetch(key_for(entry), [])
      end

      private
        attr_reader :examples

        def key_for(entry)
          [ entry.account_id, direction(entry), self.class.merchant_key(entry.name) ]
        end

        def direction(entry)
          return "payment" if entry.transaction.kind == "cc_payment"
          return "transfer" if entry.transaction.kind == "funds_movement"

          entry.amount.negative? ? "inflow" : "outflow"
        end
    end
  end
end
