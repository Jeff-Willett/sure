module Myfin
  module ClassificationSheet
    class JpwTagSync
      PREFIX = "JPW:"

      def self.call(transaction:, category_name:)
        new(transaction:, category_name:).call
      end

      def initialize(transaction:, category_name:)
        @transaction = transaction
        @category_name = category_name.to_s.strip
      end

      def call
        raise ArgumentError, "JPW category is required" if category_name.blank?

        transaction.with_lock do
          family = transaction.entry.account.family
          managed_tag_ids = family.tags.where("name LIKE ?", "#{PREFIX}%").pluck(:id)
          transaction.taggings.where(tag_id: managed_tag_ids).delete_all
          tag = family.tags.find_or_create_by!(name: "#{PREFIX} #{category_name}")
          transaction.taggings.find_or_create_by!(tag:)
          tag
        end
      end

      private
        attr_reader :transaction, :category_name
    end
  end
end
