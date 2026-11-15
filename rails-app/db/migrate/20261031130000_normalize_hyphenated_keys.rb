# RF-06 (WHA-20): listas e variáveis com hífen no nome ganhavam chave com hífen ("e2e-lista"), que não casa
# com {{chave}} (\w): a mensagem saía com o {{lista:e2e-lista}} literal. Troca o hífen por "_" nas chaves e em
# tudo que aponta para elas. Só dados; o código anterior funciona com as chaves novas (rollback seguro).
# ponytail: colisão (já existe "a_b" ao lado de "a-b") mantém a lista "a-b", mas as referências passam a "a_b";
# raro (dois nomes que só diferem no hífen) e visível no painel.
class NormalizeHyphenatedKeys < ActiveRecord::Migration[8.1]
  class List < ActiveRecord::Base; self.table_name = "member_lists"; end
  class Group < ActiveRecord::Base; self.table_name = "whatsapp_groups"; end
  class Tmpl < ActiveRecord::Base; self.table_name = "templates"; end
  class FlowRow < ActiveRecord::Base; self.table_name = "flows"; end
  class Rule < ActiveRecord::Base; self.table_name = "group_rules"; end

  PLACEHOLDER = /(?<!@)\{\{([\w:-]+)\}\}/

  def up
    fix = ->(key) { key.is_a?(String) ? key.tr("-", "_") : key }
    fix_keys = ->(hash) { hash.to_h.transform_keys(&fix).merge(hash.to_h.reject { |key, _| key.include?("-") }) } # "a_b" existente vence

    List.where("key LIKE '%-%'").find_each do |list|
      list.update_columns(key: fix.(list.key)) unless List.exists?(whatsapp_group_id: list.whatsapp_group_id, key: fix.(list.key))
    end
    Group.find_each { |group| group.update_columns(variables: fix_keys.(group.variables)) if group.variables.keys.any? { |k| k.include?("-") } }
    Tmpl.find_each do |template|
      body = template.body.gsub(PLACEHOLDER) { "{{#{fix.(Regexp.last_match(1))}}}" }
      defaults = fix_keys.(template.default_variables)
      template.update_columns(body: body, default_variables: defaults) if body != template.body || defaults != template.default_variables
    end
    FlowRow.find_each do |flow|
      steps = flow.steps.map { |step| step.merge(step.slice("list_key", "name").transform_values(&fix)) }
      flow.update_columns(steps: steps) if steps != flow.steps
    end
    Rule.find_each do |rule|
      settings = rule.settings.merge(rule.settings.slice("tracked_lists", "charged_lists").transform_values { |keys| Array(keys).map(&fix) })
      rule.update_columns(settings: settings) if settings != rule.settings
    end
  end

  def down = nil
end
