require "test_helper"

class MyfinTransactionExplorerReportTest < ActiveSupport::TestCase
  setup do
    @user = users(:family_admin)
    @family = @user.family
    Myfin::BootstrapFamily.call(family: @family)
    @personal = @family.myfin_entities.find_by!(name: "JPW Personal")
    @donna = @family.myfin_entities.find_by!(name: "Donna")
    @gci = @family.myfin_entities.find_by!(name: "Green Capital Investing")
    @jpw_scheme = @family.myfin_category_schemes.find_by!(name: "JPW")
    @gci_scheme = @family.myfin_category_schemes.find_by!(name: "GCI")
    @dis_scheme = @family.myfin_category_schemes.find_by!(name: "DIS")
    @wdg_scheme = @family.myfin_category_schemes.find_by!(name: "WDG")
    @everything_profile = @family.myfin_reporting_profiles.find_by!(name: "Everything")
    @wdg_profile = @family.myfin_reporting_profiles.find_by!(name: "WDG Report")
  end

  test "keeps JPW and Donna Shopping separate in Everything" do
    jpw_shopping = @jpw_scheme.scheme_categories.create!(name: "Entity-aware Shopping")
    dis_shopping = @dis_scheme.scheme_categories.create!(name: "Entity-aware Shopping")
    jpw_entry = create_entity_entry(entity: @personal, scheme: @jpw_scheme, category: jpw_shopping, amount: 90)
    donna_entry = create_entity_entry(entity: @donna, scheme: @dis_scheme, category: dis_shopping, amount: 50)

    report = Myfin::TransactionExplorer::Report.call(
      user: @user,
      profile: @everything_profile,
      filters: Myfin::TransactionExplorer::Filters.from_params({})
    )

    entity_rows = report.rows.select { |row| [ jpw_entry.id, donna_entry.id ].include?(row.entry_id) }
    assert_equal [ dis_shopping.id, jpw_shopping.id ].sort, entity_rows.map(&:detail_category_id).sort
    assert_equal %w[DIS JPW], entity_rows.map(&:detail_scheme_name).sort
    assert_equal [ "Entity-aware Shopping", "Entity-aware Shopping" ], entity_rows.map(&:detail_category).sort
  end

  test "WDG Report includes JPW only and derives its grouping" do
    restaurants = @jpw_scheme.scheme_categories.create!(name: "Entity-aware Restaurants")
    wdg_shopping = @wdg_scheme.scheme_categories.create!(name: "Entity-aware WDG Shopping")
    dis_restaurants = @dis_scheme.scheme_categories.create!(name: "Entity-aware Restaurants")
    Myfin::CategoryRollupMapping.create!(source_category: restaurants, target_category: wdg_shopping)
    personal_entry = create_entity_entry(entity: @personal, scheme: @jpw_scheme, category: restaurants, amount: 90)
    donna_entry = create_entity_entry(entity: @donna, scheme: @dis_scheme, category: dis_restaurants, amount: 50)

    report = Myfin::TransactionExplorer::Report.call(
      user: @user,
      profile: @wdg_profile,
      filters: Myfin::TransactionExplorer::Filters.from_params({})
    )

    assert_includes report.rows.map(&:entry_id), personal_entry.id
    assert_not_includes report.rows.map(&:entry_id), donna_entry.id
    row = report.rows.find { |candidate| candidate.entry_id == personal_entry.id }
    assert_equal "Entity-aware WDG Shopping", row.wdg_rollup
    assert_equal wdg_shopping.id, row.wdg_rollup_id
    assert_equal "wdg", report.rollup_mode
  end

  test "filters entity categories and WDG rollups by durable ID" do
    restaurants = @jpw_scheme.scheme_categories.create!(name: "ID-filter Restaurants")
    shopping = @wdg_scheme.scheme_categories.create!(name: "ID-filter Shopping")
    Myfin::CategoryRollupMapping.create!(source_category: restaurants, target_category: shopping)
    matching = create_entity_entry(entity: @personal, scheme: @jpw_scheme, category: restaurants, amount: 90)
    create_entity_entry(
      entity: @personal,
      scheme: @jpw_scheme,
      category: @jpw_scheme.scheme_categories.create!(name: "ID-filter Other"),
      amount: 50
    )

    report = Myfin::TransactionExplorer::Report.call(
      user: @user,
      profile: @wdg_profile,
      filters: Myfin::TransactionExplorer::Filters.from_params(
        detail_category_ids: [ restaurants.id ],
        wdg_rollup_ids: [ shopping.id ]
      )
    )

    assert_equal [ matching.id ], report.rows.map(&:entry_id)
  end

  test "includes and excludes an event tag from the same monthly set" do
    category = @jpw_scheme.scheme_categories.create!(name: "Tag-filter Shopping")
    setup_tag = @family.tags.create!(name: "Apartment Setup 2026", color: "#e99537")
    ordinary = create_entity_entry(entity: @personal, scheme: @jpw_scheme, category: category, amount: 40)
    event = create_entity_entry(entity: @personal, scheme: @jpw_scheme, category: category, amount: 90)
    event.transaction.tags << setup_tag

    included = Myfin::TransactionExplorer::Report.call(
      user: @user,
      profile: @everything_profile,
      filters: Myfin::TransactionExplorer::Filters.from_params(include_tag_ids: [ setup_tag.id ])
    )
    excluded = Myfin::TransactionExplorer::Report.call(
      user: @user,
      profile: @everything_profile,
      filters: Myfin::TransactionExplorer::Filters.from_params(exclude_tag_ids: [ setup_tag.id ])
    )

    assert_equal [ event.id ], included.rows.map(&:entry_id)
    assert_includes excluded.rows.map(&:entry_id), ordinary.id
    assert_not_includes excluded.rows.map(&:entry_id), event.id
    assert_equal included.rows.sum(&:amount), included.rollup.sum(&:amount)
    assert_equal excluded.rows.sum(&:amount), excluded.rollup.sum(&:amount)
    assert_equal [ setup_tag.id ], included.rows.first.tag_ids
    assert_equal [ setup_tag.name ], included.rows.first.tag_names
  end

  test "hides legacy category tags while keeping event tags" do
    category = @jpw_scheme.scheme_categories.create!(name: "Clean-tag Shopping")
    event_tag = @family.tags.create!(name: "Apartment Setup 2026", color: "#e99537")
    legacy_tag = @family.tags.create!(name: "JPW: Shopping", color: "#e99537")
    entry = create_entity_entry(entity: @personal, scheme: @jpw_scheme, category: category, amount: 90)
    entry.transaction.tags << [ event_tag, legacy_tag ]

    report = Myfin::TransactionExplorer::Report.call(
      user: @user,
      profile: @everything_profile,
      filters: Myfin::TransactionExplorer::Filters.from_params(include_tag_ids: [ legacy_tag.id ])
    )

    assert_includes report.tag_options.map(&:id), event_tag.id
    assert_not_includes report.tag_options.map(&:id), legacy_tag.id
    assert report.tag_options.none? { |tag| tag.name.match?(/\A(?:JPW|GCI|DIS|WDG):\s/) }
    assert_includes report.filter_options.tags, [ event_tag.id, event_tag.name ]
    assert_not_includes report.filter_options.tags, [ legacy_tag.id, legacy_tag.name ]
    assert_equal [ event_tag.id ], report.rows.find { |row| row.entry_id == entry.id }.tag_ids
    assert_equal [ event_tag.name ], report.rows.find { |row| row.entry_id == entry.id }.tag_names
  end

  test "fails closed for a cross-family include tag and ignores it for exclusion" do
    category = @jpw_scheme.scheme_categories.create!(name: "Cross-family tag Shopping")
    entry = create_entity_entry(entity: @personal, scheme: @jpw_scheme, category: category, amount: 40)
    other_tag = families(:empty).tags.create!(name: "Other family tag", color: "#e99537")

    included = Myfin::TransactionExplorer::Report.call(
      user: @user,
      profile: @everything_profile,
      filters: Myfin::TransactionExplorer::Filters.from_params(include_tag_ids: [ other_tag.id ])
    )
    excluded = Myfin::TransactionExplorer::Report.call(
      user: @user,
      profile: @everything_profile,
      filters: Myfin::TransactionExplorer::Filters.from_params(exclude_tag_ids: [ other_tag.id ])
    )

    assert_empty included.rows
    assert_includes excluded.rows.map(&:entry_id), entry.id
  end

  test "an empty optional WDG filter preserves non-JPW entities" do
    dis_shopping = @dis_scheme.scheme_categories.create!(name: "Optional WDG Donna Shopping")
    donna_entry = create_entity_entry(
      entity: @donna,
      scheme: @dis_scheme,
      category: dis_shopping,
      amount: 50
    )

    report = Myfin::TransactionExplorer::Report.call(
      user: @user,
      profile: @everything_profile,
      filters: Myfin::TransactionExplorer::Filters.from_params(wdg_rollup_ids: [ "__none__" ])
    )

    assert_includes report.rows.map(&:entry_id), donna_entry.id
  end

  test "loads entries once and preserves selected allocation amounts" do
    personal_entry = create_entry(
      entity_amounts: { @personal => 40 },
      date: Date.new(2026, 8, 6),
      name: "Report personal expense",
      amount: 40
    )
    shared_entry = create_entry(
      entity_amounts: { @personal => 60, @gci => 40 },
      date: Date.new(2026, 8, 5),
      name: "Report shared expense",
      amount: 100
    )
    filters = Myfin::TransactionExplorer::Filters.from_params(
      entity_ids: [ @personal.id ], years: [ "2026" ], months: [ "8" ]
    )

    report = Myfin::TransactionExplorer::Report.call(user: @user, filters: filters)

    assert_equal [ personal_entry.id, shared_entry.id ], report.rows.map(&:entry_id)
    assert_equal(-60.to_d, report.rows.find { |row| row.entry_id == shared_entry.id }.amount)
    assert_equal(
      {
        @personal.id => -60.to_d,
        @gci.id => -40.to_d
      },
      report.working_rows.find { |row| row.entry_id == shared_entry.id }.entity_amounts
    )
    assert_equal 2, report.metrics.transactions
    assert_equal report.rows.sum(&:amount), report.rollup.sum(&:amount)

    ActiveRecord::Base.connection.clear_query_cache
    queries = capture_sql_queries do
      Myfin::TransactionExplorer::Report.call(user: @user, filters: filters)
    end
    entry_loads = queries.count { |sql| sql.include?('FROM "entries"') && sql.include?("entryable_type") }
    assert_equal 1, entry_loads
  end

  test "uses one filtered row set for rollup and deterministic ordering" do
    personal_expense = create_entry(
      entity_amounts: { @personal => 120 },
      date: Date.new(2026, 8, 5),
      name: "Frame personal expense",
      amount: 120,
      wdg: "Shopping",
      jpw: "Groceries"
    )
    personal_income = create_entry(
      entity_amounts: { @personal => -3000 },
      date: Date.new(2026, 8, 14),
      name: "Frame personal income",
      amount: -3000,
      wdg: "Transfer",
      jpw: "Income"
    )
    create_entry(
      entity_amounts: { @gci => 75 },
      date: Date.new(2026, 8, 6),
      name: "Frame GCI expense",
      amount: 75,
      account: accounts(:credit_card),
      wdg: "GCI Office Expense",
      jpw: "GCI Business Software"
    )
    filters = Myfin::TransactionExplorer::Filters.from_params(
      entity_ids: [ @personal.id ],
      years: [ "2026" ],
      months: [ "8" ],
      types: %w[Expense Income]
    )

    report = Myfin::TransactionExplorer::Report.call(user: @user, filters: filters)

    assert_equal [ personal_income.id, personal_expense.id ], report.rows.map(&:entry_id)
    rollup_rows = report.rollup.flat_map do |type|
      type.groups.flat_map do |group|
        group.categories.map { |category| [ type.type, group.wdg, category.jpw, category.amount, category.count ] }
      end
    end

    assert_equal [
      [ "Expense", "Shopping", "Groceries", -120.to_d, 1 ],
      [ "Income", "Transfer", "Income", 3000.to_d, 1 ]
    ], rollup_rows
    assert_equal report.rows.sum(&:amount), report.rollup.sum(&:amount)
  end

  test "nets credits in an expense category instead of reporting them as income" do
    purchase = create_entry(
      entity_amounts: { @personal => 120 },
      date: Date.new(2026, 8, 5),
      name: "Refund net test purchase",
      amount: 120,
      wdg: "Shopping",
      jpw: "Shopping"
    )
    refund = create_entry(
      entity_amounts: { @personal => -20 },
      date: Date.new(2026, 8, 6),
      name: "Refund net test refund",
      amount: -20,
      wdg: "Shopping",
      jpw: "Shopping"
    )

    report = Myfin::TransactionExplorer::Report.call(
      user: @user,
      profile: @everything_profile,
      filters: Myfin::TransactionExplorer::Filters.from_params(
        entity_ids: [ @personal.id ],
        search: "refund net test"
      )
    )
    rows = report.rows.select { |row| [ purchase.id, refund.id ].include?(row.entry_id) }

    assert_equal %w[Refund Expense], rows.map(&:type)
    assert_equal 100.to_d, report.metrics.expenses
    assert_equal 0.to_d, report.metrics.income
    expense_rollup = report.rollup.find { |rollup| rollup.type == "Expense" }
    shopping = expense_rollup.groups.flat_map(&:categories).find { |category| category.jpw == "Shopping" }
    assert_equal(-100.to_d, shopping.amount)
    assert_equal 2, shopping.count

    expense_only = Myfin::TransactionExplorer::Report.call(
      user: @user,
      profile: @everything_profile,
      filters: Myfin::TransactionExplorer::Filters.from_params(
        entity_ids: [ @personal.id ],
        types: [ "Expense" ],
        search: "refund net test"
      )
    )
    income_only = Myfin::TransactionExplorer::Report.call(
      user: @user,
      profile: @everything_profile,
      filters: Myfin::TransactionExplorer::Filters.from_params(
        entity_ids: [ @personal.id ],
        types: [ "Income" ],
        search: "refund net test"
      )
    )

    assert_equal [ refund.id, purchase.id ], expense_only.rows.map(&:entry_id)
    assert_empty income_only.rows
  end

  test "available slicers retain unselected entities and classification values" do
    create_entry(
      entity_amounts: { @personal => 120 },
      date: Date.new(2026, 8, 5),
      name: "Frame personal option",
      amount: 120,
      wdg: "Shopping",
      jpw: "Groceries"
    )
    create_entry(
      entity_amounts: { @gci => 75 },
      date: Date.new(2025, 6, 6),
      name: "Frame GCI option",
      amount: 75,
      account: accounts(:credit_card),
      wdg: "GCI Office Expense",
      jpw: "GCI Business Software"
    )
    filters = Myfin::TransactionExplorer::Filters.from_params(entity_ids: [ @personal.id ])

    report = Myfin::TransactionExplorer::Report.call(user: @user, filters: filters)

    assert_equal [
      [ @gci.id, "CGI" ],
      [ @personal.id, "JPW" ]
    ], report.filter_options.entities
    assert_equal [ 2025, 2026 ], report.filter_options.years
    assert_equal [ 6, 8 ], report.filter_options.months
    assert_equal [ "GCI Office Expense", "Shopping" ], report.filter_options.wdg_categories
    assert_equal [ "GCI Business Software", "Groceries" ], report.filter_options.jpw_categories
    assert_equal({
      entity_ids: [ @personal.id.to_s ],
      years: %w[2025 2026],
      months: %w[6 8],
      types: [ "Expense" ],
      wdg_categories: [ "GCI Office Expense", "Shopping" ],
      jpw_categories: [ "GCI Business Software", "Groceries" ]
    }, report.selected_filters.slice(
      :entity_ids,
      :years,
      :months,
      :types,
      :wdg_categories,
      :jpw_categories
    ))
    assert_equal report.filter_options.detail_categories.map { |category| category.first.to_s },
      report.selected_filters[:detail_category_ids]
    assert_empty report.selected_filters[:wdg_rollup_ids]
  end

  test "category availability respects every filter except its own category group" do
    create_entry(
      entity_amounts: { @personal => 120 },
      date: Date.new(2026, 8, 5),
      name: "Camping living expense",
      amount: 120,
      wdg: "Other Living Expenses",
      jpw: "Camping1"
    )
    create_entry(
      entity_amounts: { @personal => 80 },
      date: Date.new(2026, 8, 6),
      name: "Camping RV expense",
      amount: 80,
      wdg: "Auto & Transport (RV)",
      jpw: "Camping1"
    )
    create_entry(
      entity_amounts: { @personal => 40 },
      date: Date.new(2026, 8, 7),
      name: "Unrelated shopping expense",
      amount: 40,
      wdg: "Shopping",
      jpw: "Groceries"
    )
    filters = Myfin::TransactionExplorer::Filters.from_params(jpw_categories: [ "Camping1" ])

    report = Myfin::TransactionExplorer::Report.call(user: @user, filters: filters)

    assert_equal Set["Auto & Transport (RV)", "Other Living Expenses"], report.category_availability[:wdg_categories]
    assert_equal Set["Camping1", "Groceries"], report.category_availability[:jpw_categories]
  end

  test "returns metrics and a hierarchical rollup from the final rows" do
    create_entry(
      entity_amounts: { @personal => 120 },
      date: Date.new(2026, 8, 5),
      name: "Report expense",
      amount: 120,
      wdg: "Shopping",
      jpw: "Groceries"
    )
    create_entry(
      entity_amounts: { @personal => -3000 },
      date: Date.new(2026, 8, 6),
      name: "Report income",
      amount: -3000,
      wdg: "Transfer",
      jpw: "Income"
    )
    create_entry(
      entity_amounts: { @personal => -500 },
      date: Date.new(2026, 8, 7),
      name: "Report transfer",
      amount: -500,
      kind: "funds_movement",
      wdg: "Transfers",
      jpw: "Transfers"
    )
    filters = Myfin::TransactionExplorer::Filters.from_params(years: [ "2026" ])

    report = Myfin::TransactionExplorer::Report.call(user: @user, filters: filters)

    assert_equal 3, report.metrics.transactions
    assert_equal 120.to_d, report.metrics.expenses
    assert_equal 3000.to_d, report.metrics.income
    assert_equal 500.to_d, report.metrics.transfer_net

    assert_equal [ "Expense", "Income", "Transfer" ], report.rollup.map(&:type)
    assert_equal "Shopping", report.rollup.first.groups.first.wdg
    assert_equal "Groceries", report.rollup.first.groups.first.categories.first.jpw
  end

  test "keeps available years when an explicit empty year selection clears rows" do
    create_entry(
      entity_amounts: { @personal => 120 },
      date: Date.new(2026, 8, 5),
      name: "Report current year",
      amount: 120
    )
    create_entry(
      entity_amounts: { @personal => 80 },
      date: Date.new(2025, 8, 5),
      name: "Report prior year",
      amount: 80
    )
    filters = Myfin::TransactionExplorer::Filters.from_params(years: [ "__none__" ])

    report = Myfin::TransactionExplorer::Report.call(user: @user, filters: filters)

    assert_empty report.rows
    assert_equal 0, report.metrics.transactions
    assert_equal BigDecimal("0"), report.metrics.expenses
    assert_equal BigDecimal("0"), report.metrics.income
    assert_equal BigDecimal("0"), report.metrics.transfer_net
    assert_empty report.rollup
    assert_equal [ 2025, 2026 ], report.filter_options.years
  end

  test "does not widen entity scope for a cross-family entity id" do
    other_entity = families(:empty).myfin_entities.create!(name: "Other Family Entity", entity_type: "person", active: true)
    personal_entry = create_entry(
      entity_amounts: { @personal => 120 },
      date: Date.new(2026, 8, 5),
      name: "Report scoped expense",
      amount: 120
    )
    filters = Myfin::TransactionExplorer::Filters.from_params(entity_ids: [ @personal.id, other_entity.id ])

    report = Myfin::TransactionExplorer::Report.call(user: @user, filters: filters)

    assert_equal [ personal_entry.id ], report.rows.map(&:entry_id)
    assert_equal [ @personal.id ], report.rows.first.entity_ids
  end

  test "exposes missing classifications as uncategorized" do
    entry = create_entry(
      entity_amounts: { @personal => 120 },
      date: Date.new(2026, 8, 5),
      name: "Report uncategorized expense",
      amount: 120
    )
    report = Myfin::TransactionExplorer::Report.call(
      user: @user,
      filters: Myfin::TransactionExplorer::Filters.from_params({})
    )

    row = report.rows.find { |candidate| candidate.entry_id == entry.id }
    assert_equal "Uncategorized", row.wdg
    assert_equal "Uncategorized", row.jpw
  end

  test "exposes editor metadata and all active category options outside the current filters" do
    wdg_scheme = @family.myfin_category_schemes.find_by!(name: "WDG")
    jpw_scheme = @family.myfin_category_schemes.find_by!(name: "JPW")
    wdg_category = wdg_scheme.scheme_categories.create!(name: "Report metadata WDG category")
    jpw_category = jpw_scheme.scheme_categories.create!(name: "Report metadata JPW category")
    available_only_in_editor = jpw_scheme.scheme_categories.create!(name: "Explorer-only JPW category")
    jpw_scheme.scheme_categories.create!(name: "Inactive Explorer category", active: false)
    entry = create_entry(
      entity_amounts: { @personal => 120 },
      date: Date.new(2026, 8, 5),
      name: "Report editor metadata",
      amount: 120,
      wdg: wdg_category.name,
      jpw: jpw_category.name
    )

    report = Myfin::TransactionExplorer::Report.call(
      user: @user,
      filters: Myfin::TransactionExplorer::Filters.from_params(wdg_categories: [ wdg_category.name ])
    )

    row = report.rows.find { |candidate| candidate.entry_id == entry.id }
    assert_equal entry.transaction_id, row.transaction_id
    assert_equal wdg_category.id, row.wdg_category_id
    assert_equal jpw_category.id, row.jpw_category_id
    assert row.editable
    assert_includes report.category_options.fetch("JPW"), [ available_only_in_editor.id, available_only_in_editor.name ]
    assert_not_includes report.category_options.fetch("JPW"), [ jpw_scheme.scheme_categories.find_by!(name: "Inactive Explorer category").id, "Inactive Explorer category" ]
  end

  test "marks rows from read-only accounts as not editable" do
    wdg_scheme = @family.myfin_category_schemes.find_by!(name: "WDG")
    jpw_scheme = @family.myfin_category_schemes.find_by!(name: "JPW")
    wdg_category = wdg_scheme.scheme_categories.create!(name: "Read-only metadata WDG category")
    jpw_category = jpw_scheme.scheme_categories.create!(name: "Read-only metadata JPW category")
    create_entry(
      entity_amounts: { @personal => 120 },
      date: Date.new(2026, 8, 5),
      name: "Report read-only editor metadata",
      amount: 120,
      account: accounts(:credit_card),
      wdg: wdg_category.name,
      jpw: jpw_category.name
    )

    report = Myfin::TransactionExplorer::Report.call(
      user: users(:family_member),
      filters: Myfin::TransactionExplorer::Filters.from_params({})
    )

    row = report.rows.find { |candidate| candidate.description == "Report read-only editor metadata" }
    assert_not row.editable
  end

  test "loads shared-account permissions once for multiple account rows" do
    member = users(:family_member)
    accounts(:investment).share_with!(member, permission: "read_write")
    entries = [ accounts(:depository), accounts(:credit_card), accounts(:investment) ].map.with_index do |account, index|
      create_entry(
        entity_amounts: { @personal => index + 1 },
        date: Date.new(2026, 8, index + 1),
        name: "Report shared-account permission #{index}",
        amount: index + 1,
        account: account
      )
    end

    ActiveRecord::Base.connection.clear_query_cache
    queries = capture_sql_queries do
      report = Myfin::TransactionExplorer::Report.call(
        user: member,
        filters: Myfin::TransactionExplorer::Filters.from_params({})
      )

      assert_equal entries.map(&:id).sort, report.rows.map(&:entry_id).sort
    end

    account_share_loads = queries.count { |sql| sql.match?(/SELECT "account_shares"\.\* FROM "account_shares"/) }
    assert_equal 1, account_share_loads
  end

  test "keeps explicitly filtered report queries within budget" do
    4.times do |index|
      create_entity_entry(
        entity: @personal,
        scheme: @jpw_scheme,
        category: @jpw_scheme.scheme_categories.create!(name: "Query budget category #{index}"),
        amount: index + 10
      )
    end

    ActiveRecord::Base.connection.clear_query_cache
    queries = capture_sql_queries do
      Myfin::TransactionExplorer::Report.call(
        user: @user,
        profile: @everything_profile,
        filters: Myfin::TransactionExplorer::Filters.from_params(entity_ids: [ @personal.id ])
      )
    end

    per_row_scheme_queries = queries.grep(
      /FROM "myfin_category_schemes" WHERE .*"entity_id".*"is_default".*LIMIT/
    )
    assert_empty per_row_scheme_queries
    assert_operator queries.size, :<=, 35
  end

  private
    def create_entity_entry(entity:, scheme:, category:, amount:)
      entry = create_entry(
        entity_amounts: { entity => amount },
        date: Date.new(2026, 8, 26),
        name: "Entity-aware sample #{category.name}",
        amount: amount
      )
      Myfin::TransactionClassification.create!(
        sure_transaction: entry.transaction,
        category_scheme: scheme,
        scheme_category: category,
        classification_source: "manual",
        confidence: 1
      )
      entry
    end

    def create_entry(entity_amounts:, date:, name:, amount:, account: accounts(:depository), kind: "standard", wdg: nil, jpw: nil)
      entry = account.entries.create!(
        entryable: Transaction.new(kind: kind),
        date: date,
        name: name,
        amount: amount,
        currency: "USD"
      )
      Myfin::EntryAllocation.replace_for!(entry, entity_amounts.map do |entity, entity_amount|
        Myfin::EntryAllocation.new(
          entity: entity,
          amount: entity_amount,
          allocation_source: "manual"
        )
      end)
      classifications = { "WDG" => wdg, "JPW" => jpw }.compact
      Myfin::Imports::ClassificationWriter.call(sure_transaction: entry.transaction, classifications:) if classifications.present?
      entry
    end
end
