require "rails_helper"

RSpec.describe "Sessions", type: :request do
  let(:username) { ENV.fetch("ADMIN_USERNAME", "admin") }
  let(:password) { ENV.fetch("ADMIN_PASSWORD") }

  it "redireciona para o login quando não autenticado" do
    get groups_path

    expect(response).to redirect_to(login_path)
  end

  it "recusa senha errada" do
    post login_path, params: { username: username, password: "errada" }

    expect(response).to have_http_status(:unprocessable_entity)
    get groups_path
    expect(response).to redirect_to(login_path)
  end

  it "entra com as credenciais do .env e sai com logout" do
    post login_path, params: { username: username, password: password }
    expect(response).to redirect_to(root_path)

    get groups_path
    expect(response).to have_http_status(:ok)

    delete logout_path
    get groups_path
    expect(response).to redirect_to(login_path)
  end
end
