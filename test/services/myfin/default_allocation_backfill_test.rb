require "test_helper"

class MyfinDefaultAllocationBackfillTest < ActiveSupport::TestCase
  setup do
    @entry = entries(:transaction)
    @family = @entry.account.family
    Myfin::BootstrapFamily.call(family: @family)
    @entity = @family.myfin_entities.find_by!(name: "JPW Personal")
    @entry.account.myfin_account_entities.create!(entity: @entity, role: "owner", ownership_percent: 100)
  end

  test "backfills only an entry with no allocation" do
    assert_difference("Myfin::EntryAllocation.count", 1) do
      Myfin::DefaultAllocationBackfill.call(entry: @entry)
    end

    assert_no_difference("Myfin::EntryAllocation.count") do
      Myfin::DefaultAllocationBackfill.call(entry: @entry)
    end

    allocation = @entry.myfin_allocations.reload.sole
    assert_equal @entity, allocation.entity
    assert_equal @entry.amount, allocation.amount
    assert_equal "account_default", allocation.allocation_source
  end
end
