class CreateSchedules < ActiveRecord::Migration[8.1]
  def change
    create_table :schedules do |t|
      t.references :template, null: false, foreign_key: true
      t.references :whatsapp_group, null: false, foreign_key: true

      t.jsonb    :variables, default: {}, null: false
      t.string   :cron_expression
      t.datetime :run_at
      t.datetime :next_run_at
      t.string   :timezone, default: "America/Sao_Paulo", null: false
      t.boolean  :active, default: true, null: false
      t.datetime :last_run_at

      t.timestamps
    end

    add_index :schedules, [ :active, :next_run_at ]
  end
end
