# The test environment is used exclusively to run your application's
# test suite. You never need to work with it otherwise. Remember that
# your test database is "scratch space" for the test suite and is wiped
# and recreated between test runs. Don't rely on the data there!

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # DB Redis separado do dev (mesmo host), para specs nao mexerem no
  # estado do Sidekiq/SendGuard rodando em desenvolvimento.
  # Sem REDIS_URL (CI), cai no localhost: antes virava só "/1" e o Sidekiq tentava um socket chamado "/1".
  ENV["REDIS_URL"] = (ENV["REDIS_URL"].presence || "redis://localhost:6379").sub(%r{/\d+\z}, "") + "/1"

  # Valores fictícios para rodar os specs sem .env (CI); o .env, quando existe, tem prioridade.
  ENV["ADMIN_PASSWORD"] ||= "test-admin-password"
  ENV["INTERNAL_API_TOKEN"] ||= "test-internal-token"
  ENV["WA_SERVICE_URL"] ||= "http://wa.test:3001"
  # A chave real do .env nunca vale em teste: cada spec que precisa da Cynth.ia liga uma fictícia.
  ENV.delete("ANTHROPIC_API_KEY")
  # Idem a URL da Anthropic falsa do e2e/.env.e2e: os specs interceptam api.anthropic.com com o WebMock.
  ENV.delete("ANTHROPIC_BASE_URL")

  # DATABASE_URL do .env aponta pro banco de dev e tem prioridade sobre
  # o database.yml mesmo com RAILS_ENV=test; sem isso, os testes rodariam
  # (e o db:schema:load bloquearia) no banco de desenvolvimento.
  ENV["DATABASE_URL"] = ENV["DATABASE_URL"].to_s.sub(/_development\z/, "_test")

  # While tests run files are not watched, reloading is not necessary.
  config.enable_reloading = false

  # Eager loading loads your entire application. When running a single test locally,
  # this is usually not necessary, and can slow down your test suite. However, it's
  # recommended that you enable it in continuous integration systems to ensure eager
  # loading is working properly before deploying your code.
  config.eager_load = ENV["CI"].present?

  # Configure public file server for tests with cache-control for performance.
  config.public_file_server.headers = { "cache-control" => "public, max-age=3600" }

  # Show full error reports.
  config.consider_all_requests_local = true
  config.cache_store = :null_store

  # Render exception templates for rescuable exceptions and raise for other exceptions.
  config.action_dispatch.show_exceptions = :rescuable

  # Disable request forgery protection in test environment.
  config.action_controller.allow_forgery_protection = false

  # Store uploaded files on the local file system in a temporary directory.
  config.active_storage.service = :test

  # Tell Action Mailer not to deliver emails to the real world.
  # The :test delivery method accumulates sent emails in the
  # ActionMailer::Base.deliveries array.
  config.action_mailer.delivery_method = :test

  # Set host to be used by links generated in mailer templates.
  config.action_mailer.default_url_options = { host: "example.com" }

  # Print deprecation notices to the stderr.
  config.active_support.deprecation = :stderr

  # Raises error for missing translations.
  config.i18n.raise_on_missing_translations = true

  # Annotate rendered view with file names.
  # config.action_view.annotate_rendered_view_with_filenames = true

  # Raise error when a before_action's only/except options reference missing actions.
  config.action_controller.raise_on_missing_callback_actions = true
end
