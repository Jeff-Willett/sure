require "test_helper"

class MyfinClassificationChangesControllerTest < ActionDispatch::IntegrationTest
  setup do
    ensure_tailwind_build
    @user = users(:family_admin)
    @entry = entries(:transaction)
    @scheme = Myfin::CategoryScheme.create!(family: @user.family, name: "JPW")
    @previous_category = Myfin::SchemeCategory.create!(category_scheme: @scheme, name: "Dining")
    @new_category = Myfin::SchemeCategory.create!(category_scheme: @scheme, name: "Coffee")
    Myfin::TransactionClassification.create!(
      sure_transaction: @entry.transaction,
      category_scheme: @scheme,
      scheme_category: @previous_category,
      classification_source: "imported"
    )
    @change = Myfin::ClassificationEditor.call(
      entry: @entry,
      scheme: @scheme,
      target_category: @new_category,
      expected_category: @previous_category,
      actor: @user,
      source: "transaction_explorer"
    ).change
    sign_in @user
  end

  test "renders entry history in a drawer" do
    get myfin_entry_classification_changes_path(@entry)

    assert_response :success
    assert_select "turbo-frame#drawer"
    assert_select "li", text: /Dining.*Coffee/m
  end

  test "reverts an accessible latest change through the editor" do
    post revert_myfin_classification_change_path(@change), as: :turbo_stream

    assert_response :success
    assert_equal "revert", Myfin::ClassificationChange.order(:created_at, :id).last.action

    get myfin_entry_classification_changes_path(@entry)

    assert_response :success
    assert_select "turbo-frame#drawer li", count: 2
    assert_select "turbo-frame#drawer li", text: /Dining.*Coffee/m, count: 1
    assert_select "turbo-frame#drawer li", text: /Coffee.*Dining.*Reverted.*Reverts an earlier change/m, count: 1
  end

  test "returns the server-current value and history link for a superseded undo" do
    post revert_myfin_classification_change_path(@change), as: :turbo_stream

    assert_response :success

    post revert_myfin_classification_change_path(@change), as: :json

    assert_response :conflict
    assert_equal "Dining", response.parsed_body.fetch("current_category")
    assert_equal myfin_entry_classification_changes_path(@entry), response.parsed_body.fetch("history_url")
  end

  test "returns not found for inaccessible entry history" do
    private_entry = create_entry(accounts(:investment), "Private entry")
    private_change = create_change(private_entry)
    accounts(:investment).account_shares.where(user: users(:family_member)).destroy_all
    sign_in users(:family_member)

    get myfin_entry_classification_changes_path(private_change.sure_transaction.entry)

    assert_response :not_found
  end

  test "forbids a read-only user from reverting an accessible change" do
    read_only_user = users(:family_member)
    @entry.account.account_shares.where(user: read_only_user).destroy_all
    @entry.account.share_with!(read_only_user, permission: "read_only")
    sign_in read_only_user

    post revert_myfin_classification_change_path(@change), as: :turbo_stream

    assert_response :forbidden
    assert_equal 1, Myfin::ClassificationChange.where(sure_transaction: @entry.transaction).count
  end

  private
    def create_entry(account, name)
      account.entries.create!(
        entryable: Transaction.new,
        name: name,
        date: Date.current,
        amount: 10,
        currency: "USD"
      )
    end

    def create_change(entry)
      Myfin::ClassificationChange.create!(
        family: @user.family,
        sure_transaction: entry.transaction,
        category_scheme: @scheme,
        actor: @user,
        previous_category: @previous_category,
        previous_category_name: @previous_category.name,
        new_category: @new_category,
        new_category_name: @new_category.name,
        action: "edit",
        source: "transaction_explorer"
      )
    end
end
