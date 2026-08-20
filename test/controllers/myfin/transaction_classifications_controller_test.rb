require "test_helper"

class Myfin::TransactionClassificationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in @user = users(:family_admin)
    @transaction = transactions(:one)
    @scheme = Myfin::CategoryScheme.create!(family: @user.family, name: "WDG")
    @category = Myfin::SchemeCategory.create!(category_scheme: @scheme, name: "Dining")
  end

  test "updates one classification for each scheme" do
    patch myfin_transaction_classifications_path(@transaction), params: {
      classifications: [
        { category_scheme_id: @scheme.id, scheme_category_id: @category.id }
      ]
    }

    assert_redirected_to transaction_path(@transaction.entry)
    classification = @transaction.myfin_classifications.reload.find_by!(category_scheme: @scheme)
    assert_equal @category, classification.scheme_category
    assert_equal "manual", classification.classification_source
    assert_equal @user, classification.reviewed_by
  end

  test "shows MyFIN dimensions alongside the transaction editor" do
    Myfin::Entity.create!(family: @user.family, name: "JPW Personal", entity_type: "person")

    get transaction_path(@transaction.entry)

    assert_response :success
    assert_select "form[action=?]", myfin_entry_allocation_path(@transaction.entry)
    assert_select "form[action=?]", myfin_transaction_classifications_path(@transaction)
    assert_select "select[name='classifications[][scheme_category_id]'] option", text: @category.name
  end

  test "replaces rather than duplicates a scheme classification" do
    old_category = Myfin::SchemeCategory.create!(category_scheme: @scheme, name: "Old")
    Myfin::TransactionClassification.create!(
      sure_transaction: @transaction,
      category_scheme: @scheme,
      scheme_category: old_category,
      classification_source: "imported"
    )

    2.times do
      patch myfin_transaction_classifications_path(@transaction), params: {
        classifications: [
          { category_scheme_id: @scheme.id, scheme_category_id: @category.id }
        ]
      }
    end

    assert_equal 1, @transaction.myfin_classifications.reload.where(category_scheme: @scheme).count
    assert_equal @category, @transaction.myfin_classifications.find_by!(category_scheme: @scheme).scheme_category
  end

  test "rejects a category from another family" do
    other_scheme = Myfin::CategoryScheme.create!(family: families(:empty), name: "Other")
    other_category = Myfin::SchemeCategory.create!(category_scheme: other_scheme, name: "Other")

    patch myfin_transaction_classifications_path(@transaction), params: {
      classifications: [
        { category_scheme_id: @scheme.id, scheme_category_id: other_category.id }
      ]
    }

    assert_response :unprocessable_entity
    assert_empty @transaction.myfin_classifications.reload
  end

  test "does not edit a read-only shared account" do
    read_only_transaction = transactions(:transfer_in)
    sign_in users(:family_member)

    patch myfin_transaction_classifications_path(read_only_transaction), params: {
      classifications: [
        { category_scheme_id: @scheme.id, scheme_category_id: @category.id }
      ]
    }

    assert_redirected_to transaction_path(read_only_transaction.entry)
    assert_empty read_only_transaction.myfin_classifications.reload
  end
end
