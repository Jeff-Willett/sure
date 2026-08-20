class CreateMyfinImportTracking < ActiveRecord::Migration[8.0]
  def change
    create_table :myfin_import_batches, id: :uuid do |t|
      t.references :family, null: false, type: :uuid, foreign_key: { on_delete: :cascade }
      t.string :source_kind, null: false
      t.string :source_locator, null: false
      t.string :source_fingerprint, null: false
      t.string :status, null: false, default: "pending"
      t.jsonb :counts, null: false, default: {}
      t.text :error_summary
      t.datetime :started_at
      t.datetime :completed_at
      t.timestamps

      t.index [ :family_id, :source_kind, :source_locator, :source_fingerprint ],
        unique: true, name: "idx_myfin_unique_import_batch"
      t.check_constraint "source_kind IN ('google_sheet', 'simplefin', 'csv', 'manual')",
        name: "chk_myfin_import_batches_source_kind"
      t.check_constraint "status IN ('pending', 'running', 'completed', 'failed')",
        name: "chk_myfin_import_batches_status"
    end

    create_table :myfin_source_records, id: :uuid do |t|
      t.references :import_batch, null: false, type: :uuid,
        foreign_key: { to_table: :myfin_import_batches, on_delete: :cascade }
      t.references :entry, type: :uuid, foreign_key: { on_delete: :nullify }
      t.string :source_record_key, null: false
      t.string :row_fingerprint, null: false
      t.jsonb :payload, null: false, default: {}
      t.string :decision, null: false
      t.string :match_method
      t.decimal :match_confidence, precision: 5, scale: 4
      t.timestamps

      t.index [ :import_batch_id, :source_record_key ], unique: true,
        name: "idx_myfin_unique_source_record"
      t.check_constraint "decision IN ('created', 'matched', 'skipped', 'review')",
        name: "chk_myfin_source_records_decision"
      t.check_constraint "match_confidence IS NULL OR (match_confidence >= 0 AND match_confidence <= 1)",
        name: "chk_myfin_source_records_confidence"
    end

    create_table :myfin_review_items, id: :uuid do |t|
      t.references :family, null: false, type: :uuid, foreign_key: { on_delete: :cascade }
      t.references :source_record, null: false, type: :uuid,
        foreign_key: { to_table: :myfin_source_records, on_delete: :cascade }
      t.string :reason, null: false
      t.string :status, null: false, default: "open"
      t.jsonb :candidate_entry_ids, null: false, default: []
      t.references :resolved_by, type: :uuid,
        foreign_key: { to_table: :users, on_delete: :nullify }
      t.datetime :resolved_at
      t.text :resolution_note
      t.timestamps

      t.index [ :source_record_id, :reason ], unique: true
      t.check_constraint "reason IN ('malformed_account', 'duplicate_candidate', 'ambiguous_match', 'uncertain_category', 'unknown_account', 'invalid_row', 'pending_replacement')",
        name: "chk_myfin_review_items_reason"
      t.check_constraint "status IN ('open', 'resolved', 'dismissed')",
        name: "chk_myfin_review_items_status"
    end
  end
end
