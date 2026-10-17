# Entrega uma mensagem já registrada em MessageLog (status pending): passa pelo SendGuard,
# envia pelo wa-service e marca o log. Usado pelos agendamentos e pelas regras de grupo.
class DeliverMessageJob
  include Sidekiq::Job

  sidekiq_options retry: 3

  def perform(message_log_id, mentions = [])
    message_log = MessageLog.find(message_log_id)

    SendGuard.check!(group_jid: message_log.group_jid, message: message_log.rendered_body)
    response = WaClient.send_message(group_jid: message_log.group_jid, message: message_log.rendered_body, mentions: mentions)
    message_log.mark_sent!(response.try(:[], "message_id"))
  rescue WaClient::NotConnected => e
    # Problema de sessão, não transiente: não deixa o Sidekiq re-tentar.
    message_log.update!(status: "failed", error_message: e.message)
  rescue SendGuard::DailyCapReachedError, SendGuard::DuplicateMessageError => e
    # Bloqueio deliberado de política: não adianta re-tentar em segundos.
    message_log.update!(status: "failed", error_message: e.message)
  rescue SendGuard::ThrottledError, WaClient::Error => e
    # Transiente: deixa o retry padrão do Sidekiq tentar de novo em breve.
    message_log.update!(status: "failed", error_message: e.message)
    raise
  end
end
