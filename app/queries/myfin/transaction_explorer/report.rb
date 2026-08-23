module Myfin
  module TransactionExplorer
    class Report
      Row = Data.define(:entry_id, :date, :description, :amount, :type, :entity_ids, :entity_names, :wdg, :jpw, :account_name)
      Metrics = Data.define(:transactions, :expenses, :income, :transfer_net)
      RollupCategory = Data.define(:jpw, :amount, :count)
      RollupGroup = Data.define(:wdg, :amount, :categories)
      RollupType = Data.define(:type, :amount, :groups)
      FilterOptions = Data.define(:entities, :years, :months, :types, :wdg_categories, :jpw_categories)
      Result = Data.define(:rows, :metrics, :rollup, :filter_options, :selected_filters)

      TYPE_ORDER = { "Expense" => 0, "Income" => 1, "Transfer" => 2 }.freeze

      def self.call(user:, filters:)
        new(user:, filters:).call
      end

      def initialize(user:, filters:)
        @user = user
        @filters = filters
      end

      def call
        available_rows = build_rows(all_entity_ids)
        rows = apply_filters(build_rows(selected_entity_ids))
        filter_options = build_filter_options(available_rows)

        Result.new(
          rows: rows,
          metrics: build_metrics(rows),
          rollup: build_rollup(rows),
          filter_options: filter_options,
          selected_filters: build_selected_filters(filter_options)
        )
      end

      private
        attr_reader :user, :filters

        def source_entries
          @source_entries ||= Entry
            .where(entryable_type: "Transaction")
            .where(account_id: user.accessible_accounts.select(:id))
            .joins(:myfin_allocations)
            .where(myfin_entry_allocations: { entity_id: all_entity_ids })
            .distinct
            .includes(:account, { myfin_allocations: :entity }, entryable: { myfin_classifications: [ :category_scheme, :scheme_category ] })
            .to_a
        end

        def source_rows
          @source_rows ||= source_entries.filter_map do |entry|
            allocations = entry.myfin_allocations.select { |allocation| all_entity_ids.include?(allocation.entity_id) }
            next if allocations.empty?

            classifications = entry.transaction.myfin_classifications.index_by { |classification| classification.category_scheme.name }
            {
              entry: entry,
              allocations: allocations,
              wdg: classifications["WDG"]&.scheme_category&.name || "Uncategorized",
              jpw: classifications["JPW"]&.scheme_category&.name || "Uncategorized"
            }
          end
        end

        def build_rows(entity_ids)
          source_rows.filter_map do |source_row|
            selected_allocations = source_row.fetch(:allocations).select do |allocation|
              entity_ids.include?(allocation.entity_id)
            end
            next if selected_allocations.empty?

            allocated_amount = selected_allocations.sum(BigDecimal("0"), &:amount)
            entry = source_row.fetch(:entry)
            transaction = entry.transaction

            Row.new(
              entry_id: entry.id,
              date: entry.date,
              description: entry.name,
              amount: allocated_amount * -1,
              type: transaction_type(transaction, allocated_amount),
              entity_ids: selected_allocations.map(&:entity_id).uniq,
              entity_names: selected_allocations.map { |allocation| allocation.entity.name }.uniq.sort,
              wdg: source_row.fetch(:wdg),
              jpw: source_row.fetch(:jpw),
              account_name: entry.account.name
            )
          end
        end

        def selected_entity_ids
          return all_entity_ids unless filters.explicit?(:entity_ids)

          user.family.myfin_entities.active.where(id: filters.values_for(:entity_ids)).pluck(:id).to_set
        end

        def all_entity_ids
          @all_entity_ids ||= user.family.myfin_entities.active.pluck(:id).to_set
        end

        def apply_filters(rows)
          rows
            .select { |row| keep_filter?(:years, row.date.year) }
            .select { |row| keep_filter?(:months, row.date.month) }
            .select { |row| keep_filter?(:types, row.type) }
            .select { |row| keep_filter?(:wdg_categories, row.wdg) }
            .select { |row| keep_filter?(:jpw_categories, row.jpw) }
            .select { |row| filters.search.blank? || row_search_text(row).include?(filters.search) }
            .sort_by { |row| [ -row.date.jd, row.entry_id ] }
        end

        def keep_filter?(key, value)
          return true unless filters.explicit?(key)

          filters.values_for(key).include?(value)
        end

        def build_metrics(rows)
          Metrics.new(
            transactions: rows.size,
            expenses: rows.select { |row| row.type == "Expense" }.sum(BigDecimal("0")) { |row| row.amount.abs },
            income: rows.select { |row| row.type == "Income" }.sum(BigDecimal("0"), &:amount),
            transfer_net: rows.select { |row| row.type == "Transfer" }.sum(BigDecimal("0"), &:amount)
          )
        end

        def build_rollup(rows)
          rows.group_by(&:type).map do |type, grouped_rows|
            RollupType.new(type: type, amount: grouped_rows.sum(BigDecimal("0"), &:amount), groups: [])
          end.sort_by { |rollup| TYPE_ORDER.fetch(rollup.type, 99) }
        end

        def build_filter_options(rows)
          entity_ids = rows.flat_map(&:entity_ids).uniq

          FilterOptions.new(
            entities: user.family.myfin_entities.active.where(id: entity_ids).order(:name).pluck(:id, :name),
            years: rows.map { |row| row.date.year }.uniq.sort,
            months: rows.map { |row| row.date.month }.uniq.sort,
            types: rows.map(&:type).uniq.sort_by { |type| TYPE_ORDER.fetch(type, 99) },
            wdg_categories: rows.map(&:wdg).uniq.sort,
            jpw_categories: rows.map(&:jpw).uniq.sort
          )
        end

        def build_selected_filters(filter_options)
          {
            entity_ids: filters.selected_values(:entity_ids, available: filter_options.entities.map(&:first)),
            years: filters.selected_values(:years, available: filter_options.years),
            months: filters.selected_values(:months, available: filter_options.months),
            types: filters.selected_values(:types, available: filter_options.types),
            wdg_categories: filters.selected_values(:wdg_categories, available: filter_options.wdg_categories),
            jpw_categories: filters.selected_values(:jpw_categories, available: filter_options.jpw_categories)
          }
        end

        def transaction_type(transaction, allocated_amount)
          return "Transfer" if %w[funds_movement cc_payment].include?(transaction.kind)

          allocated_amount.negative? ? "Income" : "Expense"
        end

        def row_search_text(row)
          [ row.description, row.account_name, row.wdg, row.jpw, *row.entity_names ]
            .join(" ")
            .downcase
        end
    end
  end
end
