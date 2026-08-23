module Myfin
  class TransactionExplorerQuery
    Row = Data.define(
      :entry_id,
      :date,
      :description,
      :amount,
      :type,
      :entity_ids,
      :entity_names,
      :wdg,
      :jpw,
      :account_name
    )
    RollupRow = Data.define(:type, :wdg, :jpw, :amount, :count)
    FilterOptions = Data.define(
      :entities,
      :years,
      :months,
      :types,
      :wdg_categories,
      :jpw_categories
    )
    Result = Data.define(:rows, :rollup_rows, :filter_options)

    TYPE_ORDER = { "Expense" => 0, "Income" => 1, "Transfer" => 2 }.freeze

    def self.call(user:, filters: {})
      new(user:, filters:).call
    end

    def initialize(user:, filters:)
      @user = user
      @filters = filters.to_h.with_indifferent_access
    end

    def call
      available_rows = build_rows(all_entity_ids)
      rows = apply_filters(build_rows(selected_entity_ids))

      Result.new(
        rows: rows,
        rollup_rows: build_rollup(rows),
        filter_options: build_filter_options(available_rows)
      )
    end

    private
      attr_reader :user, :filters

      def build_rows(entity_ids)
        entries_scope(entity_ids).map do |entry|
          selected_allocations = entry.myfin_allocations.select do |allocation|
            entity_ids.include?(allocation.entity_id)
          end
          allocated_amount = selected_allocations.sum(BigDecimal("0"), &:amount)
          classifications = entry.transaction.myfin_classifications.index_by do |classification|
            classification.category_scheme.name
          end

          Row.new(
            entry_id: entry.id,
            date: entry.date,
            description: entry.name,
            amount: allocated_amount * -1,
            type: transaction_type(entry.transaction, allocated_amount),
            entity_ids: selected_allocations.map(&:entity_id).uniq,
            entity_names: selected_allocations.map { |allocation| allocation.entity.name }.uniq.sort,
            wdg: classifications["WDG"]&.scheme_category&.name || "Uncategorized",
            jpw: classifications["JPW"]&.scheme_category&.name || "Uncategorized",
            account_name: entry.account.name
          )
        end
      end

      def entries_scope(entity_ids)
        Entry
          .where(entryable_type: "Transaction")
          .where(account_id: user.accessible_accounts.select(:id))
          .joins(:myfin_allocations)
          .where(myfin_entry_allocations: { entity_id: entity_ids })
          .distinct
          .includes(
            :account,
            { myfin_allocations: :entity },
            entryable: { myfin_classifications: [ :category_scheme, :scheme_category ] }
          )
      end

      def selected_entity_ids
        @selected_entity_ids ||= begin
          requested = Array(filters[:entity_ids]).compact_blank
          if requested.any?
            user.family.myfin_entities.active.where(id: requested).pluck(:id).to_set
          else
            all_entity_ids
          end
        end
      end

      def all_entity_ids
        @all_entity_ids ||= user.family.myfin_entities.active.pluck(:id).to_set
      end

      def apply_filters(rows)
        years = integer_filter(:years)
        months = integer_filter(:months)
        types = string_filter(:types)
        wdg_categories = string_filter(:wdg_categories)
        jpw_categories = string_filter(:jpw_categories)
        search = filters[:search].to_s.strip.downcase

        rows
          .select { |row| years.empty? || years.include?(row.date.year) }
          .select { |row| months.empty? || months.include?(row.date.month) }
          .select { |row| types.empty? || types.include?(row.type) }
          .select { |row| wdg_categories.empty? || wdg_categories.include?(row.wdg) }
          .select { |row| jpw_categories.empty? || jpw_categories.include?(row.jpw) }
          .select { |row| search.blank? || row_search_text(row).include?(search) }
          .sort_by { |row| [ -row.date.jd, row.entry_id ] }
      end

      def build_rollup(rows)
        rows
          .group_by { |row| [ row.type, row.wdg, row.jpw ] }
          .map do |(type, wdg, jpw), grouped_rows|
            RollupRow.new(
              type: type,
              wdg: wdg,
              jpw: jpw,
              amount: grouped_rows.sum(BigDecimal("0"), &:amount),
              count: grouped_rows.size
            )
          end
          .sort_by { |row| [ TYPE_ORDER.fetch(row.type, 99), -row.amount.abs, row.wdg, row.jpw ] }
      end

      def build_filter_options(rows)
        entity_ids = rows.flat_map(&:entity_ids).uniq

        FilterOptions.new(
          entities: user.family.myfin_entities.where(id: entity_ids).order(:name).pluck(:id, :name),
          years: rows.map { |row| row.date.year }.uniq.sort,
          months: rows.map { |row| row.date.month }.uniq.sort,
          types: rows.map(&:type).uniq.sort_by { |type| TYPE_ORDER.fetch(type, 99) },
          wdg_categories: rows.map(&:wdg).uniq.sort,
          jpw_categories: rows.map(&:jpw).uniq.sort
        )
      end

      def transaction_type(transaction, allocated_amount)
        return "Transfer" if %w[funds_movement cc_payment].include?(transaction.kind)

        allocated_amount.negative? ? "Income" : "Expense"
      end

      def integer_filter(key)
        Array(filters[key]).compact_blank.map(&:to_i).to_set
      end

      def string_filter(key)
        Array(filters[key]).compact_blank.map(&:to_s).to_set
      end

      def row_search_text(row)
        [ row.description, row.account_name, row.wdg, row.jpw, *row.entity_names ]
          .join(" ")
          .downcase
      end
  end
end
