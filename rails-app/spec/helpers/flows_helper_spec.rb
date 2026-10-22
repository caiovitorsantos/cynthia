require "rails_helper"

RSpec.describe FlowsHelper, type: :helper do
  it "pluraliza em português" do
    expect(helper.rough_frequency_in_words(7 * 86_400)).to eq("a cada 7 dias")
    expect(helper.rough_frequency_in_words(86_400)).to eq("a cada 1 dia")
    expect(helper.rough_frequency_in_words(2 * 3_600)).to eq("a cada 2 horas")
    expect(helper.rough_frequency_in_words(300)).to eq("a cada 5 minutos")
  end
end
