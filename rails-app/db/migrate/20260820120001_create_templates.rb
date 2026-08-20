class CreateTemplates < ActiveRecord::Migration[8.1]
  def change
    create_table :templates do |t|
      t.string  :name, null: false
      t.text    :body, null: false
      t.jsonb   :default_variables, default: {}, null: false
      t.boolean :active, default: true, null: false

      t.timestamps
    end

    add_index :templates, :name, unique: true
  end
end
