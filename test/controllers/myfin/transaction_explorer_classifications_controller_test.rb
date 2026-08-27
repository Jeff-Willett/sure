require "test_helper"

class Myfin::TransactionExplorerClassificationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:family_admin)
    @family = @user.family
    Myfin::BootstrapFamily.call(family: @family)
    @personal = @family.myfin_entities.find_by!(name: "JPW Personal")
    @jpw_scheme = @family.myfin_category_schemes.find_by!(name: "JPW")
    @old_category = @jpw_scheme.scheme_categories.create!(name: "Explorer original JPW category")
    @new_category = @jpw_scheme.scheme_categories.create!(name: "Explorer updated JPW category")
    @stale_category = @jpw_scheme.scheme_categories.create!(name: "Explorer stale JPW category")
    sign_in @user
  end

  test "updates a classification and refreshes the filtered explorer once as Turbo streams" do
    entry = create_entry(jpw: @old_category.name)

    patch myfin_entry_transaction_explorer_classification_path(entry), params: explorer_params(
      entry: entry,
      category_id: @new_category.id,
      expected_category_id: @old_category.id,
      jpw_categories: [ @old_category.name ]
    ), as: :turbo_stream

    assert_response :success
    assert_equal @new_category, entry.transaction.myfin_classifications.reload.find_by!(category_scheme: @jpw_scheme).scheme_category
    assert_equal "transaction_explorer", Myfin::ClassificationChange.order(:created_at).last.source
    assert_select "turbo-stream[action='replace'][target='transaction-explorer-shared-set']"
    assert_select "turbo-stream[action='replace'][target='transaction-explorer-metrics']"
    assert_select "turbo-stream[action='replace'][target='transaction-explorer-rollup']"
    assert_select "turbo-stream[action='replace'][target='transaction-explorer-ledger']"
    assert_select "turbo-stream[action='replace'][target='transaction-explorer-filters']"
    assert_select "turbo-stream[action='append'][target='notification-tray']"
    assert_select "turbo-stream[action='update'][target='transaction-explorer-edit-result'] template [data-entry-id='#{entry.id}'][data-scheme='JPW'][data-focus-fallback]"
    assert_select "turbo-stream[target='transaction-explorer-shared-set'] template [data-ledger-count='0'][data-rollup-count='0']"
  end

  test "sets a classification to uncategorized when category_id is blank" do
    entry = create_entry(jpw: @old_category.name)

    patch myfin_entry_transaction_explorer_classification_path(entry), params: explorer_params(
      entry: entry,
      category_id: nil,
      expected_category_id: @old_category.id
    ), as: :turbo_stream

    assert_response :success
    assert_nil entry.transaction.myfin_classifications.reload.find_by(category_scheme: @jpw_scheme)
    assert_nil Myfin::ClassificationChange.order(:created_at).last.new_category
  end

  test "does not edit a read-only account" do
    entry = entries(:transfer_in)
    entry.account.account_shares.where(user: users(:family_member)).destroy_all
    entry.account.share_with!(users(:family_member), permission: "read_only")
    sign_in users(:family_member)

    assert_no_difference -> { Myfin::ClassificationChange.count } do
      patch myfin_entry_transaction_explorer_classification_path(entry), params: explorer_params(
        entry: entry,
        category_id: @new_category.id,
        expected_category_id: nil
      ), as: :turbo_stream
    end

    assert_response :success
    assert_includes response.body, 'action="redirect"'
  end

  test "returns conflict when the expected category is stale" do
    entry = create_entry(jpw: @old_category.name)

    assert_no_difference -> { Myfin::ClassificationChange.count } do
      patch myfin_entry_transaction_explorer_classification_path(entry), params: explorer_params(
        entry: entry,
        category_id: @new_category.id,
        expected_category_id: @stale_category.id
      ), as: :turbo_stream
    end

    assert_response :conflict
    assert_equal @old_category, entry.transaction.myfin_classifications.reload.find_by!(category_scheme: @jpw_scheme).scheme_category
  end

  test "returns unprocessable entity for an inactive or out-of-family category" do
    entry = create_entry(jpw: @old_category.name)
    inactive_category = @jpw_scheme.scheme_categories.create!(name: "Inactive controller category", active: false)
    other_scheme = Myfin::CategoryScheme.create!(family: families(:empty), name: "Outside family WDG")

    patch myfin_entry_transaction_explorer_classification_path(entry), params: explorer_params(
      entry: entry,
      category_id: inactive_category.id,
      expected_category_id: @old_category.id
    ), as: :turbo_stream

    assert_response :unprocessable_entity

    patch myfin_entry_transaction_explorer_classification_path(entry), params: explorer_params(
      entry: entry,
      scheme_id: other_scheme.id,
      category_id: nil,
      expected_category_id: nil
    ), as: :turbo_stream

    assert_response :unprocessable_entity
  end

  test "renders every target used by the classification update response" do
    ensure_tailwind_build

    get myfin_transaction_explorer_path

    assert_response :success
    %w[
      transaction-explorer-shared-set
      transaction-explorer-metrics
      transaction-explorer-rollup
      transaction-explorer-ledger
      transaction-explorer-filters
      transaction-explorer-edit-result
    ].each do |target|
      assert_select "##{target}", count: 1
    end
  end

  private
    def create_entry(jpw:)
      entry = accounts(:depository).entries.create!(
        entryable: Transaction.new,
        date: Date.new(2026, 8, 5),
        name: "Explorer controller entry",
        amount: 120,
        currency: "USD"
      )
      Myfin::EntryAllocation.replace_for!(entry, [
        Myfin::EntryAllocation.new(entity: @personal, amount: 120, allocation_source: "manual")
      ])
      Myfin::Imports::ClassificationWriter.call(
        sure_transaction: entry.transaction,
        classifications: { "JPW" => jpw }
      )
      entry
    end

    def explorer_params(entry:, category_id:, expected_category_id:, scheme_id: @jpw_scheme.id, **filters)
      {
        entry_id: entry.id,
        scheme_id: scheme_id,
        category_id: category_id,
        expected_category_id: expected_category_id,
        **filters
      }
    end
end
