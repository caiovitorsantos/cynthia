require "rails_helper"

RSpec.describe Template do
  describe "#variable_names" do
    it "detecta variáveis comuns" do
      template = Template.new(body: "Olá {{nome}}, hoje é {{dia}}.")

      expect(template.variable_names).to contain_exactly("nome", "dia")
    end

    it "ignora tokens de menção (@{{...}})" do
      template = Template.new(body: "Oi @{{Caio}}, olha {{aviso}}.")

      expect(template.variable_names).to contain_exactly("aviso")
    end

    it "detecta variáveis com parâmetro" do
      template = Template.new(body: "{{lista:mensal}} {{pendentes}}")

      expect(template.variable_names).to contain_exactly("lista:mensal", "pendentes")
    end

    it "detecta {{...}} que não casa com VARIABLE_PATTERN (sairia literal)" do
      expect(Template.new(body: "{{lista:e2e-lista}} @{{Ana Paula}}").variable_names).to eq([ "lista:e2e-lista" ])
    end
  end

  it ".key_for troca hífen e espaço por _" do
    expect([ Template.key_for("e2e-lista"), Template.key_for("Chave - Pix"), Template.key_for("Mensal") ]).to eq(%w[e2e_lista chave_pix mensal])
  end

  it "RF-06: migração troca hífen por _ nas chaves e referências" do
    require Rails.root.join("db/migrate/20261031130000_normalize_hyphenated_keys")
    group = WhatsappGroup.create!(jid: "g1@g.us", name: "G", variables: { "chave-pix" => "x@y" })
    list = group.member_lists.create!(name: "e2e lista")
    list.update_columns(key: "e2e-lista")
    template = group.templates.create!(name: "T", body: "{{lista:e2e-lista}} {{chave-pix}} @{{Ana-Paula}}")
    flow = group.flows.new(name: "F", trigger: "command", command: "!f", steps: [ { "type" => "clear_list", "list_key" => "e2e-lista" } ])
    flow.save!(validate: false)
    rule = group.group_rules.create!(kind: "attendance", settings: { "tracked_lists" => [ "e2e-lista" ] })

    ActiveRecord::Migration.suppress_messages { NormalizeHyphenatedKeys.new.up }

    expect(list.reload.key).to eq("e2e_lista")
    expect(group.reload.variables).to eq("chave_pix" => "x@y")
    expect(template.reload.body).to eq("{{lista:e2e_lista}} {{chave_pix}} @{{Ana-Paula}}")
    expect(flow.reload.steps.first["list_key"]).to eq("e2e_lista")
    expect(rule.reload.settings["tracked_lists"]).to eq([ "e2e_lista" ])
    expect(TemplateRenderer.call(template, {}, whatsapp_group: group).body).not_to include("{{")
  end
end
