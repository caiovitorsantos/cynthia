# Variáveis da lista de presença passaram a receber a categoria como parâmetro.
class RenameAttendanceVariables < ActiveRecord::Migration[8.1]
  RENAMES = {
    "lista_mensais" => "lista:mensal",
    "mencoes_mensais" => "mencoes:mensal",
    "lista_espera" => "lista:espera",
    "presenca_mensais" => "presenca:mensal",
    "presenca_avulsos" => "confirmados",
    "mencoes_pendentes" => "pendentes"
  }.freeze

  def up
    RENAMES.each do |old_name, new_name|
      execute "UPDATE templates SET body = REPLACE(body, '{{#{old_name}}}', '{{#{new_name}}}') WHERE body LIKE '%{{#{old_name}}}%'"
    end
  end

  def down
    RENAMES.each do |old_name, new_name|
      execute "UPDATE templates SET body = REPLACE(body, '{{#{new_name}}}', '{{#{old_name}}}') WHERE body LIKE '%{{#{new_name}}}%'"
    end
  end
end
