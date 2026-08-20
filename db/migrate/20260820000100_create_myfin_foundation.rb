class CreateMyfinFoundation < ActiveRecord::Migration[8.0]
  def change
    create_table :myfin_entities, id: :uuid do |t|
      t.references :family, null: false, type: :uuid, foreign_key: { on_delete: :cascade }
      t.string :name, null: false
      t.string :entity_type, null: false
      t.boolean :active, null: false, default: true
      t.timestamps

      t.index [ :family_id, :name ], unique: true
      t.check_constraint "entity_type IN ('person', 'business', 'household', 'other')",
        name: "chk_myfin_entities_type"
    end

    create_table :myfin_account_entities, id: :uuid do |t|
      t.references :account, null: false, type: :uuid, foreign_key: { on_delete: :cascade }
      t.references :entity, null: false, type: :uuid,
        foreign_key: { to_table: :myfin_entities, on_delete: :cascade }
      t.string :role, null: false, default: "owner"
      t.decimal :ownership_percent, precision: 7, scale: 4, null: false, default: 100
      t.date :starts_on
      t.date :ends_on
      t.timestamps

      t.index [ :account_id, :entity_id, :starts_on ], unique: true,
        name: "idx_myfin_account_entity_period"
      t.check_constraint "role IN ('owner', 'joint_owner', 'custodian', 'reporting_only')",
        name: "chk_myfin_account_entities_role"
      t.check_constraint "ownership_percent >= 0 AND ownership_percent <= 100",
        name: "chk_myfin_account_entities_percent"
      t.check_constraint "ends_on IS NULL OR starts_on IS NULL OR ends_on >= starts_on",
        name: "chk_myfin_account_entities_dates"
    end

    create_table :myfin_entry_allocations, id: :uuid do |t|
      t.references :entry, null: false, type: :uuid, foreign_key: { on_delete: :cascade }
      t.references :entity, null: false, type: :uuid,
        foreign_key: { to_table: :myfin_entities, on_delete: :restrict }
      t.decimal :amount, precision: 19, scale: 4, null: false
      t.string :allocation_source, null: false
      t.timestamps

      t.index [ :entry_id, :entity_id ], unique: true
      t.check_constraint "allocation_source IN ('account_default', 'manual', 'rule', 'import')",
        name: "chk_myfin_entry_allocations_source"
    end

    create_table :myfin_category_schemes, id: :uuid do |t|
      t.references :family, null: false, type: :uuid, foreign_key: { on_delete: :cascade }
      t.references :entity, type: :uuid,
        foreign_key: { to_table: :myfin_entities, on_delete: :nullify }
      t.string :name, null: false
      t.boolean :is_default, null: false, default: false
      t.timestamps

      t.index [ :family_id, :name ], unique: true
      t.index :family_id, unique: true, where: "is_default",
        name: "idx_myfin_one_default_category_scheme"
    end

    create_table :myfin_scheme_categories, id: :uuid do |t|
      t.references :category_scheme, null: false, type: :uuid,
        foreign_key: { to_table: :myfin_category_schemes, on_delete: :cascade },
        index: { name: "idx_myfin_scheme_category_scheme" }
      t.references :parent, type: :uuid,
        foreign_key: { to_table: :myfin_scheme_categories, on_delete: :restrict }
      t.string :name, null: false
      t.boolean :active, null: false, default: true
      t.string :color, null: false, default: "#6172F3"
      t.string :lucide_icon, null: false, default: "shapes"
      t.timestamps

      t.index [ :category_scheme_id, :parent_id, :name ], unique: true,
        where: "parent_id IS NOT NULL", name: "idx_myfin_unique_child_scheme_category"
      t.index [ :category_scheme_id, :name ], unique: true,
        where: "parent_id IS NULL", name: "idx_myfin_unique_root_scheme_category"
    end

    create_table :myfin_transaction_classifications, id: :uuid do |t|
      t.references :transaction, null: false, type: :uuid, foreign_key: { on_delete: :cascade }
      t.references :category_scheme, null: false, type: :uuid,
        foreign_key: { to_table: :myfin_category_schemes, on_delete: :restrict },
        index: { name: "idx_myfin_classification_scheme" }
      t.references :scheme_category, null: false, type: :uuid,
        foreign_key: { to_table: :myfin_scheme_categories, on_delete: :restrict },
        index: { name: "idx_myfin_classification_category" }
      t.string :classification_source, null: false
      t.decimal :confidence, precision: 5, scale: 4
      t.uuid :rule_id
      t.datetime :reviewed_at
      t.references :reviewed_by, type: :uuid,
        foreign_key: { to_table: :users, on_delete: :nullify }
      t.timestamps

      t.index [ :transaction_id, :category_scheme_id ], unique: true,
        name: "idx_myfin_one_classification_per_scheme"
      t.check_constraint "classification_source IN ('imported', 'manual', 'rule', 'model')",
        name: "chk_myfin_classifications_source"
      t.check_constraint "confidence IS NULL OR (confidence >= 0 AND confidence <= 1)",
        name: "chk_myfin_classifications_confidence"
    end

    create_table :myfin_reporting_profiles, id: :uuid do |t|
      t.references :family, null: false, type: :uuid, foreign_key: { on_delete: :cascade }
      t.references :preferred_category_scheme, type: :uuid,
        foreign_key: { to_table: :myfin_category_schemes, on_delete: :nullify },
        index: { name: "idx_myfin_profile_preferred_scheme" }
      t.string :name, null: false
      t.boolean :is_default, null: false, default: false
      t.timestamps

      t.index [ :family_id, :name ], unique: true
      t.index :family_id, unique: true, where: "is_default",
        name: "idx_myfin_one_default_reporting_profile"
    end

    create_table :myfin_reporting_profile_entities, id: :uuid do |t|
      t.references :reporting_profile, null: false, type: :uuid,
        foreign_key: { to_table: :myfin_reporting_profiles, on_delete: :cascade },
        index: { name: "idx_myfin_profile_entity_profile" }
      t.references :entity, null: false, type: :uuid,
        foreign_key: { to_table: :myfin_entities, on_delete: :cascade }
      t.timestamps

      t.index [ :reporting_profile_id, :entity_id ], unique: true,
        name: "idx_myfin_unique_profile_entity"
    end
  end
end
