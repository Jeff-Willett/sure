class CreateMyfinClassificationExports < ActiveRecord::Migration[8.0]
  def change
    create_table :myfin_classification_exports, id: :uuid do |t|
      t.references :family, null: false, type: :uuid, foreign_key: { on_delete: :cascade }
      t.uuid :batch_id, null: false
      t.string :spreadsheet_id
      t.integer :row_count, null: false, default: 0
      t.string :data_fingerprint
      t.string :dry_run_fingerprint
      t.datetime :exported_at, null: false
      t.datetime :applied_at
      t.timestamps

      t.index [ :family_id, :batch_id ], unique: true
      t.index :spreadsheet_id, unique: true, where: "spreadsheet_id IS NOT NULL"
    end
  end
end
