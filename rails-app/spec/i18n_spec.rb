require "rails_helper"

RSpec.describe "Traduções" do
  def keys(hash, prefix = nil)
    hash.flat_map { |key, value| value.is_a?(Hash) ? keys(value, [ prefix, key ].compact.join(".")) : [ [ prefix, key ].compact.join(".") ] }
  end

  it "pt-BR, en e es têm as mesmas chaves" do
    by_locale = %w[pt-BR en es].to_h { |locale| [ locale, keys(YAML.load_file(Rails.root.join("config/locales/#{locale}.yml"))[locale]) ] }

    expect(by_locale["en"]).to match_array(by_locale["pt-BR"])
    expect(by_locale["es"]).to match_array(by_locale["pt-BR"])
  end

  it "TC-28: o aviso de IA existe nos três idiomas e cita presença/pagamento, Anthropic, os dados e que só responde marcada" do
    {
      "pt-BR" => [ "presença", "pagou", "Anthropic", "nunca o telefone", "chave Pix", "Só respondo quando me marcam" ],
      "en" => [ "attendance", "paid", "Anthropic", "never phone numbers", "Pix key", "only answer when mentioned" ],
      "es" => [ "asistencia", "pagó", "Anthropic", "nunca el teléfono", "clave Pix", "Solo respondo cuando me mencionan" ]
    }.each do |locale, words|
      expect(I18n.t("assistant.group.ai_notice", locale: locale)).to include(*words)
    end
  end
end
