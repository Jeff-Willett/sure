class CreateMyfinClassificationChanges < ActiveRecord::Migration[8.0]
  def change
    create_table :myfin_classification_changes, id: :uuid do |t|
      t.references :family, null: false, type: :uuid,
        foreign_key: { on_delete: :cascade },
        index: false
      t.references :transaction, null: false, type: :uuid,
        foreign_key: { on_delete: :cascade },
        index: false
      t.references :category_scheme, null: false, type: :uuid,
        foreign_key: { to_table: :myfin_category_schemes, on_delete: :restrict },
        index: false
      t.references :actor, type: :uuid,
        foreign_key: { to_table: :users, on_delete: :nullify },
        index: false
      t.references :previous_category, type: :uuid,
        foreign_key: { to_table: :myfin_scheme_categories, on_delete: :nullify },
        index: false
      t.string :previous_category_name
      t.references :new_category, type: :uuid,
        foreign_key: { to_table: :myfin_scheme_categories, on_delete: :nullify },
        index: false
      t.string :new_category_name
      t.references :reverted_change, type: :uuid,
        foreign_key: { to_table: :myfin_classification_changes, on_delete: :nullify },
        index: false
      t.string :action, null: false
      t.string :source, null: false
      t.timestamps

      t.index [ :family_id, :created_at ]
      t.index [ :transaction_id, :category_scheme_id, :created_at ],
        name: "idx_myfin_classification_change_history"
      t.index :reverted_change_id
      t.check_constraint "action IN ('edit', 'revert')",
        name: "chk_myfin_classification_changes_action"
      t.check_constraint "source IN ('transaction_explorer')",
        name: "chk_myfin_classification_changes_source"
    end
  end
end
