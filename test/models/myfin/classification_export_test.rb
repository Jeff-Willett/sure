require "test_helper"

class MyfinClassificationExportTest < ActiveSupport::TestCase
  test "batch id is unique within a family" do
    export = Myfin::ClassificationExport.create!(
      family: families(:dylan_family),
      batch_id: SecureRandom.uuid,
      exported_at: Time.current
    )

    duplicate = export.dup

    assert_not duplicate.valid?
  end
end
