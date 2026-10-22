require "rails_helper"

RSpec.describe "Página inicial", type: :request do
  it "apresenta a Cynth.ia para quem não está logado" do
    get root_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("cuida do seu grupo", "cynthia-badge", "Entrar no painel", "Como funciona")
  end

  it "manda quem está logado direto para os grupos" do
    post login_path, params: { username: ENV.fetch("ADMIN_USERNAME", "admin"), password: ENV.fetch("ADMIN_PASSWORD") }
    expect(response).to redirect_to(groups_path)

    get root_path
    expect(response).to redirect_to(groups_path)
  end
end
