module Myfin
  class ImportBatch < ApplicationRecord
    self.table_name = "myfin_import_batches"

    SOURCE_KINDS = %w[google_sheet simplefin csv manual].freeze
    STATUSES = %w[pending running completed failed].freeze

    belongs_to :family
    has_many :source_records,
      class_name: "Myfin::SourceRecord",
      inverse_of: :import_batch,
      dependent: :destroy

    validates :source_kind, inclusion: { in: SOURCE_KINDS }
    validates :source_locator, :source_fingerprint, presence: true
    validates :status, inclusion: { in: STATUSES }
    validates :source_fingerprint,
      uniqueness: { scope: [ :family_id, :source_kind, :source_locator ] }
  end
end
