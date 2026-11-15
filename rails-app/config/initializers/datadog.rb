# Datadog APM (ADR-012). Off unless DD_TRACE_ENABLED=true, which only the `datadog` profile of the production
# compose sets; development, test and a production without the agent run with tracing disabled.
# The gem also reads DD_SERVICE, DD_ENV, DD_VERSION and DD_AGENT_HOST from the environment (unified tagging).
# Request parameters, bodies and SQL values are not sent: the gem obfuscates SQL and does not capture params.
Datadog.configure do |c|
  c.tracing.enabled = ENV["DD_TRACE_ENABLED"] == "true"
  next unless c.tracing.enabled

  c.service = ENV.fetch("DD_SERVICE", "cynthia")
  c.tracing.instrument :rails
  c.tracing.instrument :sidekiq
  c.tracing.instrument :pg
  c.tracing.instrument :redis
  c.tracing.instrument :faraday
end
