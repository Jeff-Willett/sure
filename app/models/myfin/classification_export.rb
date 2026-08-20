module Myfin
  class ClassificationExport < ApplicationRecord
    self.table_name = "myfin_classification_exports"

    belongs_to :family

    validates :batch_id, :exported_at, presence: true
    validates :batch_id, uniqueness: { scope: :family_id }
    validates :spreadsheet_id, uniqueness: true, allow_nil: true
    validates :row_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  end
end
