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
end
