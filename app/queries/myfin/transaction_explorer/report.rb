module Myfin
  module TransactionExplorer
    class Report
      class ProfileFamilyMismatch < StandardError; end

      Row = Data.define(
        :entry_id,
        :transaction_id,
        :date,
        :description,
        :amount,
        :type,
        :entity_ids,
        :entity_names,
        :entity_amounts,
        :entity_labels,
        :transfer,
        :wdg,
        :wdg_category_id,
        :jpw,
        :jpw_category_id,
        :entity_id,
        :entity_name,
        :detail_scheme_name,
        :detail_category_id,
        :detail_category,
        :wdg_rollup_id,
        :wdg_rollup,
        :tag_ids,
        :tag_names,
        :classification_status,
        :account_name,
        :editable
      )
      Metrics = Data.define(:transactions, :expenses, :income, :transfer_net)
      RollupCategory = Data.define(:jpw, :detail_category_id, :amount, :count)
      RollupGroup = Data.define(:wdg, :entity_id, :wdg_rollup_id, :amount, :categories)
      RollupType = Data.define(:type, :amount, :groups)
      FilterOptions = Data.define(
        :entities,
        :years,
        :months,
        :types,
        :wdg_categories,
        :jpw_categories,
        :detail_categories,
        :wdg_rollups,
        :tags
      )
      Result = Data.define(
        :rows,
        :working_rows,
        :metrics,
        :rollup,
        :filter_options,
        :category_options,
        :selected_filters,
        :category_availability,
        :rollup_mode,
        :tag_options,
        :excluded_tag_names,
        :profile_name,
        :profile_scheme_name
      )

      TYPE_ORDER = { "Expense" => 0, "Refund" => 1, "Income" => 2, "Transfer" => 3 }.freeze
      LEGACY_CATEGORY_TAG = /\A(?:JPW|GCI|DIS|WDG):\s/.freeze

      def self.call(user:, filters:, profile: nil)
        new(user:, filters:, profile:).call
      end

      def initialize(user:, filters:, profile:)
        @user = user
        @filters = filters
        @profile = profile
      end

      def call
        raise ProfileFamilyMismatch if profile && profile.family_id != user.family_id

        available_rows = build_rows(all_entity_ids)
        working_rows = profile_entity_ids == all_entity_ids ? available_rows : build_rows(profile_entity_ids)
        selected_rows = selected_entity_ids == profile_entity_ids ? working_rows : build_rows(selected_entity_ids)
        rows = apply_filters(selected_rows)
        filter_options = build_filter_options(available_rows)

        Result.new(
          rows: rows,
          working_rows: working_rows,
          metrics: build_metrics(rows),
          rollup: build_rollup(rows),
          filter_options: filter_options,
          category_options: build_category_options,
          selected_filters: build_selected_filters(filter_options),
          category_availability: build_category_availability(selected_rows),
          rollup_mode: rollup_mode,
          tag_options: visible_tags(user.family.tags.alphabetically.to_a),
          excluded_tag_names: user.family.tags.where(id: exclude_tag_ids).alphabetically.pluck(:name),
          profile_name: profile&.name,
          profile_scheme_name: profile&.preferred_category_scheme&.name
        )
      end

      private
        attr_reader :user, :filters, :profile

        def source_entries
          @source_entries ||= Entry
            .where(entryable_type: "Transaction")
            .where(account_id: user.accessible_accounts.select(:id))
            .joins(:myfin_allocations)
            .where(myfin_entry_allocations: { entity_id: all_entity_ids })
            .distinct
            .includes(
              account: :account_shares,
              myfin_allocations: { entity: :category_schemes },
              entryable: [
                :tags,
                {
                  myfin_classifications: [
                    :category_scheme,
                    { scheme_category: :wdg_rollup_category }
                  ]
                }
              ]
            )
            .to_a
        end

        def source_rows
          @source_rows ||= source_entries.filter_map do |entry|
            allocations = entry.myfin_allocations.select { |allocation| all_entity_ids.include?(allocation.entity_id) }
            next if allocations.empty?

            classifications = entry.transaction.myfin_classifications.index_by { |classification| classification.category_scheme.name }
            wdg_classification = classifications["WDG"]
            jpw_classification = classifications["JPW"]
            {
              entry: entry,
              allocations: allocations,
              wdg: wdg_classification&.scheme_category&.name || "Uncategorized",
              wdg_category_id: wdg_classification&.scheme_category_id,
              jpw: jpw_classification&.scheme_category&.name || "Uncategorized",
              jpw_category_id: jpw_classification&.scheme_category_id
            }
          end
        end

        def build_rows(entity_ids)
          rows = source_rows.filter_map do |source_row|
            selected_allocations = source_row.fetch(:allocations).select do |allocation|
              entity_ids.include?(allocation.entity_id)
            end
            next if selected_allocations.empty?

            allocated_amount = selected_allocations.sum(BigDecimal("0"), &:amount)
            entry = source_row.fetch(:entry)
            transaction = entry.transaction
            transaction_tags = visible_tags(transaction.tags)
            context = Myfin::EntityCategoryContext.call(entry: entry)
            wdg_label = context.wdg_rollup&.name || source_row.fetch(:wdg)
            wdg_id = context.wdg_rollup&.id || source_row.fetch(:wdg_category_id)
            detail_label = context.detail_category&.name || source_row.fetch(:jpw)
            detail_id = context.detail_category&.id || source_row.fetch(:jpw_category_id)

            Row.new(
              entry_id: entry.id,
              transaction_id: transaction.id,
              date: entry.date,
              description: entry.name,
              amount: allocated_amount * -1,
              type: transaction_type(transaction, allocated_amount),
              entity_ids: selected_allocations.map(&:entity_id).uniq,
              entity_names: selected_allocations.map { |allocation| allocation.entity.display_name }.uniq.sort,
              entity_amounts: selected_allocations.to_h do |allocation|
                [ allocation.entity_id, allocation.amount * -1 ]
              end,
              entity_labels: selected_allocations.to_h do |allocation|
                [ allocation.entity_id, allocation.entity.display_name ]
              end,
              transfer: transfer?(transaction),
              wdg: wdg_label,
              wdg_category_id: wdg_id,
              jpw: detail_label,
              jpw_category_id: detail_id,
              entity_id: context.entity&.id,
              entity_name: context.entity&.display_name,
              detail_scheme_name: context.scheme&.name,
              detail_category_id: context.detail_category&.id,
              detail_category: context.detail_category&.name || "Uncategorized",
              wdg_rollup_id: context.wdg_rollup&.id,
              wdg_rollup: context.wdg_rollup&.name,
              tag_ids: transaction_tags.map(&:id).sort,
              tag_names: transaction_tags.map(&:name).sort,
              classification_status: context.status,
              account_name: entry.account.name,
              editable: editable?(entry)
            )
          end

          classify_refunds(rows)
        end

        def selected_entity_ids
          available = profile_entity_ids
          return available unless filters.explicit?(:entity_ids)

          requested = user.family.myfin_entities.active.where(id: filters.values_for(:entity_ids)).pluck(:id).to_set
          requested & available
        end

        def all_entity_ids
          @all_entity_ids ||= user.family.myfin_entities.active.pluck(:id).to_set
        end

        def profile_entity_ids
          @profile_entity_ids ||= if profile
            profile.entities.active.pluck(:id).to_set
          else
            all_entity_ids
          end
        end

        def apply_filters(rows)
          apply_filters_except(rows)
        end

        def apply_filters_except(rows, excluded_key = nil)
          rows
            .select { |row| excluded_key == :years || keep_filter?(:years, row.date.year) }
            .select { |row| excluded_key == :months || keep_filter?(:months, row.date.month) }
            .select { |row| excluded_key == :types || type_filter_match?(row) }
            .select { |row| excluded_key == :wdg_categories || keep_filter?(:wdg_categories, row.wdg) }
            .select { |row| excluded_key == :jpw_categories || keep_filter?(:jpw_categories, row.jpw) }
            .select { |row| excluded_key == :detail_category_ids || keep_filter?(:detail_category_ids, row.detail_category_id) }
            .select { |row| excluded_key == :wdg_rollup_ids || optional_filter_match?(:wdg_rollup_ids, row.wdg_rollup_id) }
            .select { |row| excluded_key == :include_tag_ids || include_tag_match?(row) }
            .reject { |row| excluded_key != :exclude_tag_ids && exclude_tag_match?(row) }
            .select { |row| filters.search.blank? || row_search_text(row).include?(filters.search) }
            .sort_by { |row| [ -row.date.jd, row.entry_id ] }
        end

        def keep_filter?(key, value)
          return true unless filters.explicit?(key)

          filters.values_for(key).include?(value)
        end

        def type_filter_match?(row)
          return true unless filters.explicit?(:types)

          selected_types = filters.values_for(:types)
          return selected_types.include?("Expense") || selected_types.include?("Refund") if row.type == "Refund"

          selected_types.include?(row.type)
        end

        def optional_filter_match?(key, value)
          return true unless filters.explicit?(key)
          return true if filters.values_for(key).empty?

          filters.values_for(key).include?(value)
        end

        def include_tag_match?(row)
          return true unless filters.explicit?(:include_tag_ids)
          return true if filters.values_for(:include_tag_ids).empty?
          return false if family_tag_ids(:include_tag_ids).empty?
          return true if include_tag_ids.empty?

          (row.tag_ids.to_set & include_tag_ids).any?
        end

        def exclude_tag_match?(row)
          exclude_tag_ids.any? && (row.tag_ids.to_set & exclude_tag_ids).any?
        end

        def include_tag_ids
          @include_tag_ids ||= valid_tag_ids(:include_tag_ids)
        end

        def exclude_tag_ids
          @exclude_tag_ids ||= valid_tag_ids(:exclude_tag_ids)
        end

        def valid_tag_ids(key)
          visible_tags(user.family.tags.where(id: family_tag_ids(key))).map(&:id).to_set
        end

        def family_tag_ids(key)
          @family_tag_ids ||= {}
          @family_tag_ids[key] ||= user.family.tags.where(id: filters.values_for(key)).pluck(:id).to_set
        end

        def visible_tags(tags)
          tags.reject { |tag| tag.name.match?(LEGACY_CATEGORY_TAG) }
        end

        def build_metrics(rows)
          expense_rows = rows.select { |row| row.type == "Expense" }
          refund_rows = rows.select { |row| row.type == "Refund" }

          Metrics.new(
            transactions: rows.size,
            expenses: expense_rows.sum(BigDecimal("0")) { |row| row.amount.abs } - refund_rows.sum(BigDecimal("0"), &:amount),
            income: rows.select { |row| row.type == "Income" }.sum(BigDecimal("0"), &:amount),
            transfer_net: rows.select { |row| row.type == "Transfer" }.sum(BigDecimal("0"), &:amount)
          )
        end

        def build_rollup(rows)
          rows.group_by { |row| row.type == "Refund" ? "Expense" : row.type }.map do |type, type_rows|
            groups = rollup_mode == "wdg" ? build_wdg_groups(type_rows) : build_entity_groups(type_rows)

            RollupType.new(
              type: type,
              amount: type_rows.sum(BigDecimal("0"), &:amount),
              groups: groups
            )
          end.sort_by { |rollup| TYPE_ORDER.fetch(rollup.type, 99) }
        end

        def build_wdg_groups(rows)
          rows.group_by { |row| [ row.wdg_rollup_id || row.wdg_category_id, row.wdg_rollup || row.wdg ] }
            .map do |(rollup_id, label), group_rows|
              RollupGroup.new(
                wdg: label,
                entity_id: nil,
                wdg_rollup_id: rollup_id,
                amount: group_rows.sum(BigDecimal("0"), &:amount),
                categories: build_rollup_categories(group_rows)
              )
            end
            .sort_by { |group| [ -group.amount.abs, group.wdg ] }
        end

        def build_entity_groups(rows)
          rows.group_by { |row| [ row.entity_id, row.entity_name || "Needs entity" ] }
            .map do |(entity_id, label), group_rows|
              RollupGroup.new(
                wdg: label,
                entity_id: entity_id,
                wdg_rollup_id: nil,
                amount: group_rows.sum(BigDecimal("0"), &:amount),
                categories: build_rollup_categories(group_rows)
              )
            end
            .sort_by { |group| [ -group.amount.abs, group.wdg ] }
        end

        def build_rollup_categories(rows)
          rows.group_by do |row|
            [ row.detail_category_id || row.jpw_category_id, row.detail_category || row.jpw ]
          end.map do |(category_id, label), category_rows|
            RollupCategory.new(
              jpw: label,
              detail_category_id: category_id,
              amount: category_rows.sum(BigDecimal("0"), &:amount),
              count: category_rows.size
            )
          end.sort_by { |category| [ -category.amount.abs, category.jpw ] }
        end

        def build_filter_options(rows)
          entity_ids = rows.flat_map(&:entity_ids).uniq
          tag_ids = rows.flat_map(&:tag_ids).uniq

          FilterOptions.new(
            entities: user.family.myfin_entities.active.where(id: entity_ids).order(:name).map { |entity|
              [ entity.id, entity.display_name ]
            },
            years: rows.map { |row| row.date.year }.uniq.sort,
            months: rows.map { |row| row.date.month }.uniq.sort,
            types: rows.map { |row| row.type == "Refund" ? "Expense" : row.type }.uniq.sort_by { |type| TYPE_ORDER.fetch(type, 99) },
            wdg_categories: rows.map(&:wdg).uniq.sort,
            jpw_categories: rows.map(&:jpw).uniq.sort,
            detail_categories: rows.filter_map do |row|
              [ row.detail_category_id, row.detail_scheme_name, row.detail_category ] if row.detail_category_id
            end.uniq.sort_by { |id, scheme, name| [ scheme, name, id ] },
            wdg_rollups: rows.filter_map do |row|
              [ row.wdg_rollup_id, row.wdg_rollup ] if row.wdg_rollup_id
            end.uniq.sort_by { |id, name| [ name, id ] },
            tags: user.family.tags.where(id: tag_ids).alphabetically.pluck(:id, :name)
          )
        end

        def build_category_options
          user.family.myfin_category_schemes
            .where(name: %w[JPW DIS GCI])
            .includes(:scheme_categories)
            .to_h do |scheme|
              categories = scheme.scheme_categories
                .select(&:active?)
                .sort_by { |category| [ category.name, category.id ] }
                .map { |category| [ category.id, category.name ] }
              [ scheme.name, categories ]
            end
        end

        def build_selected_filters(filter_options)
          {
            entity_ids: filters.selected_values(:entity_ids, available: filter_options.entities.map(&:first)),
            years: filters.selected_values(:years, available: filter_options.years),
            months: filters.selected_values(:months, available: filter_options.months),
            types: filters.selected_values(:types, available: filter_options.types),
            wdg_categories: filters.selected_values(:wdg_categories, available: filter_options.wdg_categories),
            jpw_categories: filters.selected_values(:jpw_categories, available: filter_options.jpw_categories),
            detail_category_ids: filters.selected_values(
              :detail_category_ids,
              available: filter_options.detail_categories.map(&:first)
            ),
            wdg_rollup_ids: selected_optional_values(:wdg_rollup_ids),
            include_tag_ids: selected_tag_values(:include_tag_ids),
            exclude_tag_ids: selected_tag_values(:exclude_tag_ids)
          }
        end

        def selected_tag_values(key)
          selected_optional_values(key)
        end

        def selected_optional_values(key)
          return [] unless filters.explicit?(key)

          filters.values_for(key).map(&:to_s)
        end

        def build_category_availability(rows)
          {
            wdg_categories: apply_filters_except(rows, :wdg_categories).map(&:wdg).uniq.to_set,
            jpw_categories: apply_filters_except(rows, :jpw_categories).map(&:jpw).uniq.to_set,
            detail_category_ids: apply_filters_except(rows, :detail_category_ids).map(&:detail_category_id).compact.to_set,
            wdg_rollup_ids: apply_filters_except(rows, :wdg_rollup_ids).map(&:wdg_rollup_id).compact.to_set,
            tag_ids: apply_filters_except(rows, :include_tag_ids).flat_map(&:tag_ids).to_set
          }
        end

        def transaction_type(transaction, allocated_amount)
          return "Transfer" if transfer?(transaction)

          allocated_amount.negative? ? "Income" : "Expense"
        end

        def transfer?(transaction)
          transaction.kind.in?(%w[funds_movement cc_payment])
        end

        def classify_refunds(rows)
          expense_category_ids = rows
            .select { |row| row.type == "Expense" }
            .map(&:detail_category_id)
            .compact
            .to_set

          rows.map do |row|
            expense_credit = row.type == "Income" &&
              row.detail_category_id.in?(expense_category_ids) &&
              (row.wdg_rollup || row.wdg) != "Transfer"

            expense_credit ? row.with(type: "Refund") : row
          end
        end

        def editable?(entry)
          entry.account.permission_for(user).in?([ :owner, :full_control, :read_write ])
        end

        def row_search_text(row)
          [
            row.description,
            row.account_name,
            row.wdg,
            row.jpw,
            row.detail_category,
            row.wdg_rollup,
            *row.entity_names
          ]
            .join(" ")
            .downcase
        end

        def rollup_mode
          return "wdg" if profile.nil? || profile.preferred_category_scheme&.name == "WDG"

          "entity"
        end
    end
  end
end
