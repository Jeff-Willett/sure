require "test_helper"

class Myfin::TransactionExplorerCellBatchesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:family_admin)
    @family = @user.family
    Myfin::BootstrapFamily.call(family: @family)
    @entity = @family.myfin_entities.find_by!(name: "JPW Personal")
    @scheme = @family.myfin_category_schemes.find_by!(name: "JPW")
    @old_category = @scheme.scheme_categories.create!(name: "Cell batch original")
    @new_category = @scheme.scheme_categories.create!(name: "Cell batch replacement")
    @old_tag = @family.tags.create!(name: "Cell batch old tag")
    @new_tags = [
      @family.tags.create!(name: "Cell batch new tag one"),
      @family.tags.create!(name: "Cell batch new tag two")
    ]
    @entry = create_entry
    sign_in @user
  end

  test "updates a category and replaces the complete tag list atomically" do
    assert_difference -> { Myfin::ClassificationChange.count }, 1 do
      patch "/myfin/transaction_explorer_cell_batch",
        params: { edits: [ category_edit, tags_edit ] },
        as: :json
    end

    assert_response :success
    classification = @entry.transaction.myfin_classifications.reload.find_by!(category_scheme: @scheme)
    assert_equal @new_category, classification.scheme_category
    assert_equal @new_tags.map(&:id).sort, @entry.transaction.tags.reload.map(&:id).sort
    assert_equal [ @entry.id ], response.parsed_body.fetch("rows").pluck("id")
  end

  test "rolls back every cell when the expected tag list is stale" do
    stale_tags_edit = tags_edit.merge(expected_tag_ids: [ @new_tags.first.id ])

    assert_no_difference -> { Myfin::ClassificationChange.count } do
      patch "/myfin/transaction_explorer_cell_batch",
        params: { edits: [ category_edit, stale_tags_edit ] },
        as: :json
    end

    assert_response :conflict
    classification = @entry.transaction.myfin_classifications.reload.find_by!(category_scheme: @scheme)
    assert_equal @old_category, classification.scheme_category
    assert_equal [ @old_tag.id ], @entry.transaction.tags.reload.map(&:id)
  end

  private
    def create_entry
      entry = accounts(:depository).entries.create!(
        entryable: Transaction.new,
        date: Date.new(2026, 8, 27),
        name: "Spreadsheet cell batch row",
        amount: 25,
        currency: "USD"
      )
      Myfin::EntryAllocation.replace_for!(entry, [
        Myfin::EntryAllocation.new(entity: @entity, amount: entry.amount, allocation_source: "manual")
      ])
      Myfin::Imports::ClassificationWriter.call(
        sure_transaction: entry.transaction,
        classifications: { "JPW" => @old_category.name }
      )
      entry.transaction.update!(tag_ids: [ @old_tag.id ])
      entry
    end

    def category_edit
      {
        field: "detail_category",
        entry_id: @entry.id,
        scheme_id: @scheme.id,
        category_id: @new_category.id,
        expected_category_id: @old_category.id
      }
    end

    def tags_edit
      {
        field: "tags",
        entry_id: @entry.id,
        tag_ids: @new_tags.map(&:id),
        expected_tag_ids: [ @old_tag.id ]
      }
    end
end
