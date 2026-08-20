class CreateMessageLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :message_logs do |t|
      t.references :schedule, foreign_key: true

      t.string  :group_jid
      t.text    :rendered_body
      t.string  :status, default: "pending", null: false
      t.text    :error_message
      t.datetime :sent_at

      t.timestamps
    end
  end
end
