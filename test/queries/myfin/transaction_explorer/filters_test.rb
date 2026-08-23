require "test_helper"

class MyfinTransactionExplorerFiltersTest < ActiveSupport::TestCase
  test "normalizes typed values and hides the no-selection sentinel" do
    filters = Myfin::TransactionExplorer::Filters.from_params(
      entity_ids: [ "entity-1", "__none__", "" ],
      years: [ "2025", "2026" ],
      months: [ "8" ],
      types: [ "Expense" ],
      search: "  rent  "
    )

    assert_equal [ "entity-1" ], filters.values_for(:entity_ids)
    assert_equal [ 2025, 2026 ], filters.values_for(:years)
    assert_equal [ 8 ], filters.values_for(:months)
    assert_equal [ "Expense" ], filters.values_for(:types)
    assert_equal "rent", filters.search
  end

  test "distinguishes absent filters from an explicit empty selection" do
    absent = Myfin::TransactionExplorer::Filters.from_params({})
    cleared = Myfin::TransactionExplorer::Filters.from_params(years: [ "__none__" ])

    assert_not absent.explicit?(:years)
    assert_equal [ "2025", "2026" ], absent.selected_values(:years, available: [ 2025, 2026 ])
    assert cleared.explicit?(:years)
    assert_empty cleared.values_for(:years)
    assert_empty cleared.selected_values(:years, available: [ 2025, 2026 ])
  end

  test "keeps normalized values and search immutable" do
    filters = Myfin::TransactionExplorer::Filters.from_params(
      years: [ "2025" ],
      search: "  rent  "
    )

    assert_raises(FrozenError) { filters.values_for(:years) << 2026 }
    assert_raises(FrozenError) { filters.search << " payment" }
    assert_equal [ 2025 ], filters.values_for(:years)
    assert_equal "rent", filters.search
  end
end
