class CreateMyfinCategoryRollupMappings < ActiveRecord::Migration[8.1]
  def up
    remove_index :myfin_category_schemes,
      name: "idx_myfin_one_default_category_scheme"
    add_index :myfin_category_schemes,
      :entity_id,
      unique: true,
      where: "is_default AND entity_id IS NOT NULL",
      name: "idx_myfin_one_default_category_scheme_per_entity"

    create_table :myfin_category_rollup_mappings, id: :uuid do |t|
      t.references :source_category,
        null: false,
        type: :uuid,
        foreign_key: { to_table: :myfin_scheme_categories, on_delete: :restrict },
        index: { unique: true, name: "idx_myfin_rollup_one_target_per_source" }
      t.references :target_category,
        null: false,
        type: :uuid,
        foreign_key: { to_table: :myfin_scheme_categories, on_delete: :restrict },
        index: { name: "idx_myfin_rollup_target" }
      t.timestamps
    end

    add_check_constraint :myfin_category_rollup_mappings,
      "source_category_id <> target_category_id",
      name: "chk_myfin_rollup_distinct_categories"
  end

  def down
    drop_table :myfin_category_rollup_mappings

    remove_index :myfin_category_schemes,
      name: "idx_myfin_one_default_category_scheme_per_entity"
    add_index :myfin_category_schemes,
      :family_id,
      unique: true,
      where: "is_default",
      name: "idx_myfin_one_default_category_scheme"
  end
end
