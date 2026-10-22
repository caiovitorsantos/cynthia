# O produto passa a ser um automatizador de grupo: listas de membros, templates e fluxos
# (gatilho + passos) pertencem a cada grupo. Converte categorias → listas, agendamentos →
# fluxos de horário, o comando da lista de presença → fluxo de comando, e copia os templates
# para cada grupo que os usa.
class ReshapeIntoGroupAutomation < ActiveRecord::Migration[8.1]
  DEFAULT_CATEGORIES = [
    { "key" => "mensal", "name" => "Mensal", "fixed" => true },
    { "key" => "avulso", "name" => "Avulso", "fixed" => false },
    { "key" => "espera", "name" => "Espera", "fixed" => false }
  ].freeze
  DEFAULT_LIST_REPLY = "*Lista de presença*\n\n{{presenca}}\n\n*Avulsos*\n{{confirmados}}".freeze

  class Group < ActiveRecord::Base
    self.table_name = "whatsapp_groups"
  end

  class Rule < ActiveRecord::Base
    self.table_name = "group_rules"
  end

  class Tpl < ActiveRecord::Base
    self.table_name = "templates"
  end

  class Sched < ActiveRecord::Base
    self.table_name = "schedules"
  end

  class FlowRow < ActiveRecord::Base
    self.table_name = "flows"
  end

  class List < ActiveRecord::Base
    self.table_name = "member_lists"
  end

  def up
    create_table :member_lists do |t|
      t.references :whatsapp_group, null: false, foreign_key: { on_delete: :cascade }
      t.string :key, null: false
      t.string :name, null: false
      t.timestamps
      t.index [ :whatsapp_group_id, :key ], unique: true
    end

    create_join_table :group_participants, :member_lists do |t|
      t.index [ :member_list_id, :group_participant_id ], unique: true, name: "index_list_members_unique"
      t.index :group_participant_id
    end
    add_foreign_key :group_participants_member_lists, :group_participants, on_delete: :cascade
    add_foreign_key :group_participants_member_lists, :member_lists, on_delete: :cascade

    add_column :whatsapp_groups, :list_style, :string, default: "numbered", null: false
    add_column :whatsapp_groups, :list_empty_text, :string, default: "", null: false

    add_reference :templates, :whatsapp_group, foreign_key: { on_delete: :cascade }
    remove_index :templates, :name
    add_index :templates, [ :whatsapp_group_id, :name ], unique: true

    create_table :flows do |t|
      t.references :whatsapp_group, null: false, foreign_key: { on_delete: :cascade }
      t.string :name, null: false
      t.boolean :active, default: true, null: false
      t.string :trigger, null: false
      t.string :command
      t.string :cron_expression
      t.datetime :run_at
      t.string :timezone, default: "America/Sao_Paulo", null: false
      t.datetime :next_run_at
      t.datetime :last_run_at
      t.jsonb :steps, default: [], null: false
      t.timestamps
      t.index [ :active, :next_run_at ]
    end

    add_reference :message_logs, :flow, foreign_key: { on_delete: :nullify }
    add_column :message_logs, :opens_round, :boolean, default: false, null: false

    Group.reset_column_information
    Tpl.reset_column_information
    migrate_lists
    template_ids = migrate_templates
    migrate_schedules(template_ids)
    migrate_list_commands(template_ids)
    migrate_rule_settings

    remove_reference :message_logs, :schedule, foreign_key: true
    drop_table :schedules
    remove_column :group_participants, :role
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end

  private

  def rules
    @rules ||= Rule.where(kind: "attendance").index_by(&:whatsapp_group_id)
  end

  # Categorias da regra (e papéis soltos) viram listas; as fixas viram listas acompanhadas
  # pela presença. A formatação de lista passa para o grupo.
  def migrate_lists
    Group.find_each do |group|
      rule = rules[group.id]
      categories = rule ? (rule.settings["categories"] || DEFAULT_CATEGORIES) : []
      roles = select_values("SELECT DISTINCT role FROM group_participants WHERE whatsapp_group_id = #{group.id} AND role IS NOT NULL")
      categories += (roles - categories.map { |category| category["key"] }).map { |role| { "key" => role, "name" => role.humanize } }

      categories.each do |category|
        list = List.create!(whatsapp_group_id: group.id, key: category["key"], name: category["name"])
        execute(<<~SQL)
          INSERT INTO group_participants_member_lists (group_participant_id, member_list_id)
          SELECT id, #{list.id} FROM group_participants
          WHERE whatsapp_group_id = #{group.id} AND role = #{connection.quote(category["key"])}
        SQL
      end

      next unless rule

      group.update!(list_style: rule.settings["list_style"] || "numbered", list_empty_text: rule.settings["empty_text"] || "1.")
      tracked[group.id] = categories.select { |category| category["fixed"] }.map { |category| category["key"] }
    end
  end

  def tracked
    @tracked ||= {}
  end

  # Por último: os passos anteriores ainda leem template_id/list_command das settings antigas.
  def migrate_rule_settings
    rules.each do |group_id, rule|
      rule.update!(settings: rule.settings.slice("confirm_emojis", "decline_emojis", "accept_replies", "confirmed_mark", "declined_mark", "pending_mark")
        .merge("tracked_lists" => tracked.fetch(group_id, [])))
    end
  end

  # Cada template fica com o primeiro grupo que o usa e é copiado para os demais. Templates
  # sem uso vão para os grupos configurados (com agendamento ou regra).
  # Devolve { [template_id_antigo, group_id] => template_id_no_grupo }.
  def migrate_templates
    configured = (Sched.distinct.pluck(:whatsapp_group_id) + rules.keys).uniq
    ids = {}

    Tpl.where(whatsapp_group_id: nil).find_each do |template|
      users = Sched.where(template_id: template.id).distinct.pluck(:whatsapp_group_id) +
              rules.select { |_, rule| [ rule.settings["template_id"], rule.settings["list_reply_template_id"] ].map(&:to_i).include?(template.id) }.keys
      users = configured if users.empty?

      users.uniq.each_with_index do |group_id, index|
        copy = index.zero? ? template : template.dup
        copy.update!(whatsapp_group_id: group_id)
        ids[[ template.id, group_id ]] = copy.id
      end
    end
    ids
  end

  # Agendamento → fluxo de horário com um passo "enviar template". O template da regra de
  # presença abre rodada. Variáveis do agendamento vão para o grupo (sem sobrescrever).
  def migrate_schedules(template_ids)
    Sched.find_each do |schedule|
      rule = rules[schedule.whatsapp_group_id]
      template_id = template_ids.fetch([ schedule.template_id, schedule.whatsapp_group_id ])
      opens_round = rule && rule.settings["template_id"].to_i == schedule.template_id

      flow = FlowRow.create!(
        whatsapp_group_id: schedule.whatsapp_group_id, name: Tpl.find(template_id).name, trigger: "schedule",
        active: schedule.active, cron_expression: schedule.cron_expression, run_at: schedule.run_at,
        timezone: schedule.timezone, next_run_at: schedule.next_run_at, last_run_at: schedule.last_run_at,
        steps: [ { "type" => "send_message", "template_id" => template_id.to_s, "opens_round" => opens_round ? "1" : "0" } ]
      )
      execute("UPDATE message_logs SET flow_id = #{flow.id}, opens_round = #{opens_round ? 'TRUE' : 'FALSE'} WHERE schedule_id = #{schedule.id}")

      group = Group.find(schedule.whatsapp_group_id)
      group.update!(variables: schedule.variables.merge(group.variables)) if schedule.variables.present?
    end
  end

  def migrate_list_commands(template_ids)
    rules.each do |group_id, rule|
      command = rule.settings.fetch("list_command", "!lista") # ausente = padrão antigo
      next if command.blank?

      reply_id = rule.settings["list_reply_template_id"].presence
      template_id = reply_id ? template_ids.fetch([ reply_id.to_i, group_id ]) : Tpl.create!(whatsapp_group_id: group_id, name: "Lista atual", body: DEFAULT_LIST_REPLY).id
      FlowRow.create!(whatsapp_group_id: group_id, name: "Responder #{command}", trigger: "command", command: command,
                      steps: [ { "type" => "send_message", "template_id" => template_id.to_s, "opens_round" => "0" } ])
    end
  end
end
