Template.find_or_create_by!(name: "Lembrete de reunião") do |template|
  template.body = "Olá {{nome}}! Lembrete: a reunião \"{{assunto}}\" começa às {{horario}}."
  template.default_variables = { "assunto" => "Alinhamento semanal" }
  template.active = true
end
