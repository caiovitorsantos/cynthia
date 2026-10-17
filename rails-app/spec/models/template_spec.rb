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
  end
end
