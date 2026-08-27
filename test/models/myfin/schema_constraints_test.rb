require "test_helper"

class MyfinSchemaConstraintsTest < ActiveSupport::TestCase
  test "foundation tables and unique indexes exist" do
    tables = ActiveRecord::Base.connection.tables

    assert_includes tables, "myfin_entities"
    assert_includes tables, "myfin_account_entities"
    assert_includes tables, "myfin_entry_allocations"
    assert_includes tables, "myfin_category_schemes"
    assert_includes tables, "myfin_scheme_categories"
    assert_includes tables, "myfin_category_rollup_mappings"
    assert_includes tables, "myfin_transaction_classifications"
    assert_includes tables, "myfin_reporting_profiles"
    assert_includes tables, "myfin_reporting_profile_entities"
    assert_includes tables, "myfin_import_batches"
    assert_includes tables, "myfin_source_records"
    assert_includes tables, "myfin_review_items"

    index = ActiveRecord::Base.connection
      .indexes(:myfin_transaction_classifications)
      .find { |candidate| candidate.name == "idx_myfin_one_classification_per_scheme" }

    assert index.unique

    rollup_index = ActiveRecord::Base.connection
      .indexes(:myfin_category_rollup_mappings)
      .find { |candidate| candidate.name == "idx_myfin_rollup_one_target_per_source" }

    assert rollup_index.unique

    default_scheme_index = ActiveRecord::Base.connection
      .indexes(:myfin_category_schemes)
      .find { |candidate| candidate.name == "idx_myfin_one_default_category_scheme_per_entity" }

    assert default_scheme_index.unique
    assert_equal [ "entity_id" ], default_scheme_index.columns
    assert_equal "(is_default AND (entity_id IS NOT NULL))", default_scheme_index.where
  end
end
