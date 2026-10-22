require "rails_helper"

RSpec.describe "Conta e conexão", type: :request do
  before { post login_path, params: { username: ENV.fetch("ADMIN_USERNAME", "admin"), password: ENV.fetch("ADMIN_PASSWORD") } }

  it "a página inicial é a lista de grupos, com o modal da conta carregando a conexão sob demanda" do
    get root_path

    expect(response.body).to include("<h1", "Grupos", "<dialog", "Sair do painel")
    expect(response.body).to include('id="account_connection"', "src=\"#{connection_path}\"", 'loading="lazy"')
    expect(response.body).not_to include(">Conexão<")
  end

  it "o status da conexão responde dentro do frame do modal" do
    stub_request(:get, "#{ENV.fetch('WA_SERVICE_URL')}/health").to_return(status: 200, body: { status: "connected" }.to_json, headers: { "Content-Type" => "application/json" })

    get connection_path

    expect(response.body).to include('<turbo-frame id="account_connection">', "conectado", "Desconectar este número")
  end
end
