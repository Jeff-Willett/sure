module Myfin
  class PreviewDataset
    class NotAllowed < StandardError; end

    Result = Data.define(:transaction_ids)

    DEFINITIONS = [
      {
        key: "jpw-apartment-shopping",
        entity: "JPW Personal",
        scheme: "JPW",
        category: "Shopping",
        wdg: "Shopping",
        name: "Sample Online Market",
        amount: 90,
        tags: [ "Apartment Setup 2026", "Discretionary" ]
      },
      {
        key: "jpw-apartment-home",
        entity: "JPW Personal",
        scheme: "JPW",
        category: "Renter Expenses",
        wdg: "Home Living",
        name: "Sample Home Store",
        amount: 40,
        tags: [ "Apartment Setup 2026" ]
      },
      {
        key: "donna-shopping",
        entity: "Donna",
        scheme: "DIS",
        category: "Shopping",
        wdg: nil,
        name: "Sample Donna Store",
        amount: 50,
        tags: []
      },
      {
        key: "gci-software",
        entity: "Green Capital Investing",
        scheme: "GCI",
        category: "Business Software",
        wdg: nil,
        name: "Sample Business Software",
        amount: 25,
        tags: []
      },
      {
        key: "jpw-restaurants",
        entity: "JPW Personal",
        scheme: "JPW",
        category: "Restaurants",
        wdg: "Shopping",
        name: "Sample Cafe",
        amount: 20,
        tags: []
      }
    ].freeze

    def self.call(family:)
      new(family).call
    end

    def initialize(family)
      @family = family
    end

    def call
      raise NotAllowed unless allowed?

      Myfin::BootstrapFamily.call(family: family)
      account = family.accounts.order(:created_at, :id).first!
      transaction_ids = DEFINITIONS.map { |definition| upsert_definition!(account, definition) }
      Result.new(transaction_ids: transaction_ids)
    end

    private
      attr_reader :family

      def allowed?
        Rails.env.test? || (
          Rails.env.development? &&
          ActiveModel::Type::Boolean.new.cast(ENV["MYFIN_PREVIEW_SAMPLE_DATA"])
        )
      end

      def upsert_definition!(account, definition)
        transaction = family.transactions
          .where("transactions.extra ->> 'myfin_preview_key' = ?", definition.fetch(:key))
          .first
        entry = transaction&.entry || build_entry!(account, definition)

        entry.update!(
          date: Date.new(2026, 4, 1),
          name: definition.fetch(:name),
          amount: definition.fetch(:amount),
          currency: family.currency
        )
        entry.transaction.update!(
          kind: "standard",
          extra: entry.transaction.extra.merge("myfin_preview_key" => definition.fetch(:key))
        )

        entity = family.myfin_entities.find_by!(name: definition.fetch(:entity))
        Myfin::EntryAllocation.replace_for!(entry, [
          Myfin::EntryAllocation.new(
            entity: entity,
            amount: entry.amount,
            allocation_source: "manual"
          )
        ])
        classify!(entry.transaction, definition)
        apply_tags!(entry.transaction, definition.fetch(:tags))
        entry.transaction.id
      end

      def build_entry!(account, definition)
        account.entries.create!(
          entryable: Transaction.new(
            kind: "standard",
            extra: { "myfin_preview_key" => definition.fetch(:key) }
          ),
          date: Date.new(2026, 4, 1),
          name: definition.fetch(:name),
          amount: definition.fetch(:amount),
          currency: family.currency
        )
      end

      def classify!(transaction, definition)
        scheme = family.myfin_category_schemes.find_by!(name: definition.fetch(:scheme))
        category = scheme.scheme_categories.find_or_create_by!(name: definition.fetch(:category))
        classification = transaction.myfin_classifications.find_or_initialize_by(category_scheme: scheme)
        classification.update!(
          scheme_category: category,
          classification_source: "manual",
          confidence: 1
        )

        return unless definition[:wdg]

        wdg_scheme = family.myfin_category_schemes.find_by!(name: "WDG")
        wdg_category = wdg_scheme.scheme_categories.find_or_create_by!(name: definition.fetch(:wdg))
        mapping = Myfin::CategoryRollupMapping.find_or_initialize_by(source_category: category)
        mapping.update!(target_category: wdg_category)
      end

      def apply_tags!(transaction, tag_names)
        tags = tag_names.map do |name|
          family.tags.find_or_create_by!(name: name) do |tag|
            tag.color = Tag::COLORS.first
          end
        end
        transaction.tags = (transaction.tags.to_a | tags)
      end
  end
end
