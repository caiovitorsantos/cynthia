require "rails_helper"

RSpec.describe TemplateRenderer do
  describe ".call" do
    it "substitui as variáveis no corpo" do
      template = Template.new(body: "Olá {{nome}}, hoje é {{dia}}.")

      result = described_class.call(template, { "nome" => "Caio", "dia" => "segunda" })

      expect(result).to eq("Olá Caio, hoje é segunda.")
    end

    it "aceita chaves como symbol" do
      template = Template.new(body: "Olá {{nome}}!")

      result = described_class.call(template, { nome: "Caio" })

      expect(result).to eq("Olá Caio!")
    end

    it "levanta erro se sobrar variável não preenchida" do
      template = Template.new(body: "Olá {{nome}}, hoje é {{dia}}.")

      expect {
        described_class.call(template, { "nome" => "Caio" })
      }.to raise_error(TemplateRenderer::MissingVariableError, /dia/)
    end

    it "não escapa nada (texto puro, não HTML)" do
      template = Template.new(body: "<b>{{tag}}</b>")

      result = described_class.call(template, { "tag" => "<script>" })

      expect(result).to eq("<b><script></b>")
    end
  end
end
