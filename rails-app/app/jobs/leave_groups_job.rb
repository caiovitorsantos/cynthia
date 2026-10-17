class LeaveGroupsJob
  include Sidekiq::Job

  # Falhas são tratadas por grupo; re-tentar o lote inteiro não ajuda.
  sidekiq_options retry: false

  # Intervalo entre saídas para não parecer automação em massa pro WhatsApp.
  DELAY_RANGE = 3..8

  def perform(group_ids)
    WhatsappGroup.where(id: group_ids).each_with_index do |group, index|
      sleep(rand(DELAY_RANGE)) if index.positive?

      WaClient.leave_group(group.jid)
      group.destroy!
    rescue WaClient::NotConnected
      Rails.logger.warn("LeaveGroupsJob: WhatsApp desconectado, interrompendo")
      return
    rescue WaClient::Error, Faraday::ConnectionFailed, Faraday::TimeoutError => e
      Rails.logger.warn("LeaveGroupsJob: falha ao sair de #{group.name} (#{group.jid}): #{e.message}")
    end
  end
end
