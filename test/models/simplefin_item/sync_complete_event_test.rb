require "test_helper"

class SimplefinItem::SyncCompleteEventTest < ActiveSupport::TestCase
  test "audits the latest completed sync before broadcasting" do
    family = families(:dylan_family)
    item = SimplefinItem.create!(
      family: family,
      name: "SimpleFIN event test",
      access_url: "https://example.com/access"
    )
    sync = item.syncs.create!(status: "completed", completed_at: Time.current)
    Myfin::SimplefinSyncAuditor.expects(:call).with(simplefin_item: item, sync: sync).once
    family.stubs(:broadcast_sync_complete)
    item.stubs(:broadcast_replace_to)

    SimplefinItem::SyncCompleteEvent.new(item).broadcast
  end
end
