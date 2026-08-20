require "test_helper"

class Myfin::EntryAllocationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in @user = users(:family_admin)
    @entry = entries(:transaction)
    @personal = Myfin::Entity.create!(family: @user.family, name: "JPW Personal", entity_type: "person")
    @business = Myfin::Entity.create!(family: @user.family, name: "Green Capital Investing", entity_type: "business")
  end

  test "replaces allocations when they total the entry amount" do
    patch myfin_entry_allocation_path(@entry), params: {
      allocations: [
        { entity_id: @personal.id, amount: "4" },
        { entity_id: @business.id, amount: "6" }
      ]
    }

    assert_redirected_to transaction_path(@entry)
    assert_equal(
      { @personal.id => BigDecimal("4"), @business.id => BigDecimal("6") },
      @entry.myfin_allocations.reload.to_h { |allocation| [ allocation.entity_id, allocation.amount ] }
    )
  end

  test "rejects allocations whose amounts do not total the entry amount" do
    patch myfin_entry_allocation_path(@entry), params: {
      allocations: [ { entity_id: @personal.id, amount: "9" } ]
    }

    assert_response :unprocessable_entity
    assert_empty @entry.myfin_allocations.reload
  end

  test "rejects an entity from another family" do
    other_entity = Myfin::Entity.create!(family: families(:empty), name: "Other", entity_type: "person")

    patch myfin_entry_allocation_path(@entry), params: {
      allocations: [ { entity_id: other_entity.id, amount: @entry.amount.to_s } ]
    }

    assert_response :unprocessable_entity
    assert_empty @entry.myfin_allocations.reload
  end

  test "does not edit a read-only shared account" do
    read_only_entry = entries(:transfer_in)
    sign_in users(:family_member)

    patch myfin_entry_allocation_path(read_only_entry), params: {
      allocations: [ { entity_id: @personal.id, amount: read_only_entry.amount.to_s } ]
    }

    assert_redirected_to transaction_path(read_only_entry)
    assert_empty read_only_entry.myfin_allocations.reload
  end
end
