# Massa E2E idempotente, tudo com prefixo e2e- e telefones com DDD 00 (inexistente).
# bin/rails runner e2e/support/seed.rb [basico|referencia]   (rodar de rails-app/, com e2e/ montado ou copiado)
# Apaga só o que é e2e- antes de recriar. Logs semeados são de ontem: não gastam a cota diária do SendGuard. Nunca rodar fora da stack E2E.
abort "seed E2E só em development/test" if Rails.env.production?

profile = ARGV.first.presence || "basico"
groups, people, logs = profile == "referencia" ? [ 30, 50, 2000 ] : [ 2, 6, 30 ]
names = %w[volei futebol] + (3..groups).map { |n| "grupo#{n}" }

MessageLog.where("group_jid LIKE 'e2e-%'").delete_all
WhatsappGroup.where("jid LIKE 'e2e-%'").find_each do |group|
  group.flows.delete_all # template em uso por fluxo não se apaga sozinho
  group.destroy!
end
AssistantMessage.delete_all
AssistantAction.delete_all

phone = 0
names.first(groups).each do |slug|
  group = WhatsappGroup.create!(jid: "e2e-#{slug}@g.us", name: "e2e-#{slug}", synced_at: Time.current,
                                variables: { "pix" => "e2e-pix@example.invalid" })
  participants = people.times.map do |i|
    phone += 1
    number = format("55000%08d", phone)
    group.group_participants.create!(jid: "#{number}@s.whatsapp.net", phone_number: number,
                                     name: (i == people - 1 ? nil : "e2e-Pessoa#{phone}"), admin: i.zero?, synced_at: Time.current)
  end
  group.update!(participants_count: participants.size)
  mensal = group.member_lists.create!(name: "Mensal", key: "mensal")
  avulsos = group.member_lists.create!(name: "Avulsos", key: "avulsos")
  participants.first(people / 2).each { |p| mensal.group_participants << p }
  participants.last(2).each { |p| avulsos.group_participants << p }

  lista = group.templates.create!(name: "e2e-lista", body: "*Lista* da semana\n{{lista:mensal}}")
  group.templates.create!(name: "e2e-cobranca", body: "Pix: {{pix}}")
  espera = group.templates.create!(name: "e2e-espera", body: "{{remetente}} entrou na espera: {{argumento}}")
  group.group_rules.create!(kind: "attendance", settings: { "tracked_lists" => [ "mensal" ] })
  group.group_rules.create!(kind: "billing", settings: { "charged_lists" => [ "mensal" ] })
  # 1 rotina + 1 comando por grupo (referência: 60 fluxos)
  group.flows.create!(name: "e2e-rotina", trigger: "schedule", cron_expression: "0 9 * * 1", timezone: "America/Sao_Paulo",
                      steps: [ { "type" => "send_message", "template_id" => lista.id.to_s } ])
  group.flows.create!(name: "e2e-espera", trigger: "command", command: "!espera",
                      steps: [ { "type" => "add_to_list", "list_key" => "avulsos" }, { "type" => "send_message", "template_id" => espera.id.to_s } ])
end

jids = WhatsappGroup.where("jid LIKE 'e2e-%'").pluck(:jid)
now = Time.current
MessageLog.insert_all!(logs.times.map do |i|
  status = i % 5 == 0 ? "failed" : "sent"
  { group_jid: jids[i % jids.size], rendered_body: "e2e-log #{i}", status: status, sent_at: (status == "sent" ? now - i.minutes - 1.day : nil),
    error_message: (status == "failed" ? "e2e: wa-service não está conectado" : nil), created_at: now - i.minutes - 1.day, updated_at: now }
end)

puts "seed #{profile}: #{WhatsappGroup.where("jid LIKE 'e2e-%'").count} grupos, #{GroupParticipant.joins(:whatsapp_group).where("whatsapp_groups.jid LIKE 'e2e-%'").count} participantes, " \
     "#{Flow.joins(:whatsapp_group).where("whatsapp_groups.jid LIKE 'e2e-%'").count} fluxos, #{MessageLog.where("group_jid LIKE 'e2e-%'").count} logs"
