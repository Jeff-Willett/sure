require "test_helper"

class Myfin::TransactionExplorerClassificationBatchesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:family_admin)
    @family = @user.family
    Myfin::BootstrapFamily.call(family: @family)
    @entity = @family.myfin_entities.find_by!(name: "JPW Personal")
    @scheme = @family.myfin_category_schemes.find_by!(name: "WDG")
    @old_category = @scheme.scheme_categories.create!(name: "Batch original")
    @new_category = @scheme.scheme_categories.create!(name: "Batch replacement")
    sign_in @user
  end

  test "updates multiple existing categories atomically and audits each cell" do
    entries = [ create_entry("Batch row one"), create_entry("Batch row two") ]

    assert_difference -> { Myfin::ClassificationChange.count }, 2 do
      patch myfin_transaction_explorer_classification_batch_path,
        params: { edits: entries.map { |entry| edit_params(entry) } },
        as: :turbo_stream
    end

    assert_response :success
    entries.each do |entry|
      classification = entry.transaction.myfin_classifications.reload.find_by!(category_scheme: @scheme)
      assert_equal @new_category, classification.scheme_category
    end
    assert_select "turbo-stream[action='replace'][target='transaction-explorer-ledger']"
  end

  test "rejects an invalid cell without applying earlier edits or creating categories" do
    entries = [ create_entry("Batch valid row"), create_entry("Batch invalid row") ]
    category_count = @scheme.scheme_categories.count

    assert_no_difference -> { Myfin::ClassificationChange.count } do
      patch myfin_transaction_explorer_classification_batch_path,
        params: {
          edits: [
            edit_params(entries.first),
            edit_params(entries.second).merge(category_id: "Unknown pasted category")
          ]
        },
        as: :turbo_stream
    end

    assert_response :unprocessable_entity
    assert_equal category_count, @scheme.scheme_categories.count
    entries.each do |entry|
      classification = entry.transaction.myfin_classifications.reload.find_by!(category_scheme: @scheme)
      assert_equal @old_category, classification.scheme_category
    end
  end

  private
    def create_entry(name)
      entry = accounts(:depository).entries.create!(
        entryable: Transaction.new,
        date: Date.new(2026, 8, 5),
        name: name,
        amount: 120,
        currency: "USD"
      )
      Myfin::EntryAllocation.replace_for!(entry, [
        Myfin::EntryAllocation.new(entity: @entity, amount: 120, allocation_source: "manual")
      ])
      Myfin::Imports::ClassificationWriter.call(
        sure_transaction: entry.transaction,
        classifications: { "WDG" => @old_category.name }
      )
      entry
    end

    def edit_params(entry)
      {
        entry_id: entry.id,
        scheme_id: @scheme.id,
        category_id: @new_category.id,
        expected_category_id: @old_category.id
      }
    end
end
