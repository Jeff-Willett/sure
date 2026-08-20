class SimplefinItem::SyncCompleteEvent
  attr_reader :simplefin_item

  def initialize(simplefin_item)
    @simplefin_item = simplefin_item
  end

  def broadcast
    audit_completed_sync

    # Update UI with latest account data
    simplefin_item.accounts.each do |account|
      account.broadcast_sync_complete
    end

    # Update the SimpleFin item view
    simplefin_item.broadcast_replace_to(
      simplefin_item.family,
      target: "simplefin_item_#{simplefin_item.id}",
      partial: "simplefin_items/simplefin_item",
      locals: { simplefin_item: simplefin_item }
    )

    # Let family handle sync notifications
    simplefin_item.family.broadcast_sync_complete
  end

  private
    def audit_completed_sync
      sync = simplefin_item.latest_completed_sync_record
      return if sync.nil?

      Myfin::SimplefinSyncAuditor.call(simplefin_item: simplefin_item, sync: sync)
    rescue StandardError => error
      Rails.logger.error("SimpleFIN sync audit failed: #{error.class.name}")
      Sentry.capture_exception(error)
    end
end
