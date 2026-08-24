require "test_helper"

class MyfinClassificationEditorTest < ActiveSupport::TestCase
  setup do
    @entry = entries(:transaction)
    @transaction = @entry.transaction
    @family = @entry.account.family
    @user = users(:family_admin)
    @jpw_scheme = Myfin::CategoryScheme.create!(family: @family, name: "JPW")
    @wdg_scheme = Myfin::CategoryScheme.create!(family: @family, name: "WDG")
    @old_jpw = Myfin::SchemeCategory.create!(category_scheme: @jpw_scheme, name: "Dining")
    @new_jpw = Myfin::SchemeCategory.create!(category_scheme: @jpw_scheme, name: "Coffee")
    @old_wdg = Myfin::SchemeCategory.create!(category_scheme: @wdg_scheme, name: "Food")
    @wdg_category = Myfin::SchemeCategory.create!(category_scheme: @wdg_scheme, name: "Restaurants")

    create_classification(@jpw_scheme, @old_jpw)
    create_classification(@wdg_scheme, @old_wdg)
  end

  test "edits one scheme and records faithful category snapshots" do
    result = call_editor(
      scheme: @jpw_scheme,
      target_category: @new_jpw,
      expected_category: @old_jpw
    )

    assert_equal @new_jpw, result.classification.reload.scheme_category
    assert_equal [ @old_jpw.name, @new_jpw.name ],
      [ result.change.previous_category_name, result.change.new_category_name ]
    assert_equal @family, result.change.family
    assert_equal @transaction, result.change.sure_transaction
    assert_equal @jpw_scheme, result.change.category_scheme
    assert_equal @user, result.change.actor
    assert_equal "edit", result.change.action
    assert_equal "transaction_explorer", result.change.source
    assert_equal @old_wdg, classification_for(@wdg_scheme).scheme_category
  end

  test "uncategorizes one scheme without changing the other scheme" do
    result = call_editor(
      scheme: @jpw_scheme,
      target_category: nil,
      expected_category: @old_jpw
    )

    assert_nil classification_for(@jpw_scheme)
    assert_equal [ @old_jpw.name, nil ],
      [ result.change.previous_category_name, result.change.new_category_name ]
    assert_nil result.change.new_category
    assert_nil result.classification
    assert_equal @old_wdg, classification_for(@wdg_scheme).scheme_category
  end

  test "mirrors a WDG edit to the native family category" do
    result = call_editor(
      scheme: @wdg_scheme,
      target_category: @wdg_category,
      expected_category: @old_wdg
    )

    assert_equal @wdg_category, result.classification.reload.scheme_category
    assert_equal @wdg_category.name, @transaction.reload.category.name
    assert_equal @family, @transaction.category.family
  end

  test "clears the native WDG category when WDG is uncategorized" do
    call_editor(
      scheme: @wdg_scheme,
      target_category: @wdg_category,
      expected_category: @old_wdg
    )

    result = call_editor(
      scheme: @wdg_scheme,
      target_category: nil,
      expected_category: @wdg_category
    )

    assert_nil result.classification
    assert_nil classification_for(@wdg_scheme)
    assert_equal [ @wdg_category.name, nil ],
      [ result.change.previous_category_name, result.change.new_category_name ]
    assert_nil @transaction.reload.category
    assert_equal @old_jpw, classification_for(@jpw_scheme).scheme_category
  end

  test "rejects a stale expected category without a write" do
    assert_no_difference -> { Myfin::TransactionClassification.count } do
      assert_no_difference -> { Myfin::ClassificationChange.count } do
        assert_raises Myfin::ClassificationEditor::StaleClassification do
          call_editor(
            scheme: @jpw_scheme,
            target_category: @new_jpw,
            expected_category: @new_jpw
          )
        end
      end
    end

    assert_equal @old_jpw, classification_for(@jpw_scheme).scheme_category
  end

  test "rejects a category from another family without a write" do
    other_scheme = Myfin::CategoryScheme.create!(family: families(:empty), name: "Other")
    other_category = Myfin::SchemeCategory.create!(category_scheme: other_scheme, name: "Other category")

    assert_no_difference -> { Myfin::TransactionClassification.count } do
      assert_no_difference -> { Myfin::ClassificationChange.count } do
        assert_raises Myfin::ClassificationEditor::InvalidCategory do
          call_editor(
            scheme: @jpw_scheme,
            target_category: other_category,
            expected_category: @old_jpw
          )
        end
      end
    end

    assert_equal @old_jpw, classification_for(@jpw_scheme).scheme_category
  end

  test "rejects a read-only actor before writing an audit or classification" do
    read_only_entry = entries(:transfer_in)

    assert_no_difference -> { Myfin::TransactionClassification.count } do
      assert_no_difference -> { Myfin::ClassificationChange.count } do
        assert_raises Myfin::ClassificationEditor::NotAuthorized do
          Myfin::ClassificationEditor.call(
            entry: read_only_entry,
            scheme: @jpw_scheme,
            target_category: @new_jpw,
            expected_category: nil,
            actor: users(:family_member),
            source: "transaction_explorer"
          )
        end
      end
    end
  end

  test "rolls back the classification and audit when WDG mirroring fails" do
    Myfin::ClassificationEditor.any_instance
      .stubs(:mirror_wdg_to_sure!)
      .raises(StandardError, "native mirror failed")

    assert_no_difference -> { Myfin::TransactionClassification.count } do
      assert_no_difference -> { Myfin::ClassificationChange.count } do
        assert_raises StandardError do
          call_editor(
            scheme: @wdg_scheme,
            target_category: @wdg_category,
            expected_category: @old_wdg
          )
        end
      end
    end

    assert_equal @old_wdg, classification_for(@wdg_scheme).scheme_category
  end

  test "reverts the latest change through the same editor" do
    edited = call_editor(
      scheme: @jpw_scheme,
      target_category: @new_jpw,
      expected_category: @old_jpw
    )

    reverted = call_editor(
      scheme: @jpw_scheme,
      target_category: nil,
      expected_category: nil,
      revert_of: edited.change
    )

    assert_equal @old_jpw, reverted.classification.reload.scheme_category
    assert_equal "revert", reverted.change.action
    assert_equal edited.change, reverted.change.reverted_change
    assert_equal [ @new_jpw.name, @old_jpw.name ],
      [ reverted.change.previous_category_name, reverted.change.new_category_name ]
  end

  test "rejects a superseded change as a revert target without a write" do
    first = call_editor(
      scheme: @jpw_scheme,
      target_category: @new_jpw,
      expected_category: @old_jpw
    )
    call_editor(
      scheme: @jpw_scheme,
      target_category: @old_jpw,
      expected_category: @new_jpw
    )

    assert_no_difference -> { Myfin::ClassificationChange.count } do
      assert_raises Myfin::ClassificationEditor::InvalidRevert do
        call_editor(
          scheme: @jpw_scheme,
          target_category: nil,
          expected_category: nil,
          revert_of: first.change
        )
      end
    end

    assert_equal @old_jpw, classification_for(@jpw_scheme).scheme_category
  end

  private
    def call_editor(scheme:, target_category:, expected_category:, revert_of: nil)
      Myfin::ClassificationEditor.call(
        entry: @entry,
        scheme: scheme,
        target_category: target_category,
        expected_category: expected_category,
        actor: @user,
        source: "transaction_explorer",
        revert_of: revert_of
      )
    end

    def classification_for(scheme)
      @transaction.myfin_classifications.reload.find_by(category_scheme: scheme)
    end

    def create_classification(scheme, category)
      Myfin::TransactionClassification.create!(
        sure_transaction: @transaction,
        category_scheme: scheme,
        scheme_category: category,
        classification_source: "imported"
      )
    end
end
