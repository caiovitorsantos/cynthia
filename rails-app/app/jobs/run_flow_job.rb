class RunFlowJob
  include Sidekiq::Job

  # ponytail: sem retry, para não repetir passos (listas, envios) de uma execução que falhou no meio.
  sidekiq_options retry: false

  def perform(flow_id, context = {})
    Flow.find(flow_id).run!(context)
  end
end
