# G8 (tracking-plan.md, ADR-011): eventos de produto no próprio Postgres. Tabela nova: o código anterior a
# ignora (rollback seguro).
class CreateAnalyticsEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :analytics_events do |t|
      t.string :name, null: false
      t.datetime :occurred_at, null: false
      t.jsonb :properties, null: false, default: {}
      t.timestamps
    end
    add_index :analytics_events, [ :name, :occurred_at ]
  end
end
