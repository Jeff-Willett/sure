require "test_helper"

class MyfinSchemaConstraintsTest < ActiveSupport::TestCase
  test "foundation tables and unique indexes exist" do
    tables = ActiveRecord::Base.connection.tables

    assert_includes tables, "myfin_entities"
    assert_includes tables, "myfin_account_entities"
    assert_includes tables, "myfin_entry_allocations"
    assert_includes tables, "myfin_category_schemes"
    assert_includes tables, "myfin_scheme_categories"
    assert_includes tables, "myfin_transaction_classifications"
    assert_includes tables, "myfin_reporting_profiles"
    assert_includes tables, "myfin_reporting_profile_entities"

    index = ActiveRecord::Base.connection
      .indexes(:myfin_transaction_classifications)
      .find { |candidate| candidate.name == "idx_myfin_one_classification_per_scheme" }

    assert index.unique
  end
end
