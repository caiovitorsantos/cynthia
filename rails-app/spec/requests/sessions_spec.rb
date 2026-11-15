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

  it "TT-01: login aceito grava admin_logado sem propriedades; senha errada não grava" do
    post login_path, params: { username: username, password: "errada" }
    expect(AnalyticsEvent.count).to eq(0)

    post login_path, params: { username: username, password: password }
    expect(AnalyticsEvent.sole).to have_attributes(name: "admin_logado", properties: {})
  end

  it "entra com as credenciais do .env e sai com logout" do
    post login_path, params: { username: username, password: password }
    expect(response).to redirect_to(groups_path)

    get groups_path
    expect(response).to have_http_status(:ok)

    delete logout_path
    get groups_path
    expect(response).to redirect_to(login_path)
  end

  it "TM-23: a 11a tentativa em 3 min é bloqueada com o alerta de limite" do
    # O teste usa :null_store, que desliga o rate_limit: aqui o store do controller passa a ser um MemoryStore.
    memory = ActiveSupport::Cache::MemoryStore.new
    store = SessionsController.cache_store
    allow(store).to receive(:increment) { |*args, **options| memory.increment(*args, **options) }

    10.times { post login_path, params: { username: username, password: "errada" } }
    expect(response).to have_http_status(:unprocessable_entity)

    post login_path, params: { username: username, password: password }
    expect(response).to redirect_to(login_path)
    expect(flash[:alert]).to eq(I18n.t("sessions.create.rate_limited"))
    get groups_path
    expect(response).to redirect_to(login_path)
  end

  it "TM-26: o limite vale mesmo quando cada tentativa manda um Forwarded: for= diferente" do
    memory = ActiveSupport::Cache::MemoryStore.new
    store = SessionsController.cache_store
    allow(store).to receive(:increment) { |*args, **options| memory.increment(*args, **options) }

    10.times { |i| post login_path, params: { username: username, password: "errada" }, headers: { "Forwarded" => "for=203.0.113.#{i}" } }
    post login_path, params: { username: username, password: password }, headers: { "Forwarded" => "for=198.51.100.99" }

    expect(response).to redirect_to(login_path)
    expect(flash[:alert]).to eq(I18n.t("sessions.create.rate_limited"))
  end
end
