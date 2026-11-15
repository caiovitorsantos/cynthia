require "rails_helper"

# O bin/docker-entrypoint só roda o db:prepare (migrações) quando o comando termina em "./bin/rails server".
# Qualquer argumento depois disso ("-p 80") sobe o Puma sem migrar e o /up fica verde com o banco desatualizado.
RSpec.describe "Dockerfile de produção" do
  it "o CMD termina em ./bin/rails server, o que o entrypoint exige para migrar" do
    cmd = Rails.root.join("Dockerfile").read.scan(/^CMD (\[.*\])$/).flatten.last
    expect(cmd).to be_present
    expect(JSON.parse(cmd).last(2)).to eq([ "./bin/rails", "server" ])
    expect(Rails.root.join("bin/docker-entrypoint").read).to include('"${@: -2:1}" == "./bin/rails"', '"${@: -1:1}" == "server"')
  end
end
