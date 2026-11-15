# Entrega uma mensagem já registrada em MessageLog (status pending): passa pelo SendGuard,
# envia pelo wa-service e marca o log. Usado pelos agendamentos e pelas regras de grupo.
# origem (tracking-plan): rotina, comando, executar_agora ou reenvio; nil nas respostas da Cynth.ia.
class DeliverMessageJob
  include Sidekiq::Job

  MAX_RETRIES = 3 # RF-18: até 3 novas tentativas nos erros transientes
  sidekiq_options retry: MAX_RETRIES

  MOTIVOS = {
    WaClient::NotConnected => "desconectado",
    SendGuard::DailyCapReachedError => "limite_diario",
    SendGuard::DuplicateMessageError => "duplicata",
    SendGuard::ThrottledError => "throttle"
  }.freeze

  def perform(message_log_id, mentions = [], origem = nil)
    message_log = MessageLog.find(message_log_id)
    attempt = next_attempt(message_log_id)

    SendGuard.check!(group_jid: message_log.group_jid, message: message_log.rendered_body)
    response = WaClient.send_message(group_jid: message_log.group_jid, message: message_log.rendered_body, mentions: mentions)
    message_log.mark_sent!(response.try(:[], "message_id"))
    self.class.track_sent(message_log, origem: origem, mentions: mentions.size, attempt: attempt)
  rescue WaClient::NotConnected => e
    # Problema de sessão, não transiente: não deixa o Sidekiq re-tentar.
    self.class.fail!(message_log, e, origem: origem)
  rescue SendGuard::DailyCapReachedError, SendGuard::DuplicateMessageError => e
    # Bloqueio deliberado de política: não adianta re-tentar em segundos.
    self.class.fail!(message_log, e, origem: origem)
  rescue SendGuard::ThrottledError, WaClient::Error => e
    # Transiente: deixa o retry padrão do Sidekiq tentar de novo em breve.
    self.class.fail!(message_log, e, origem: origem, retrying: attempt <= MAX_RETRIES)
    raise
  end

  def self.fail!(message_log, error, origem:, retrying: false)
    message_log.update!(status: "failed", error_message: error.message)
    AnalyticsEvent.track(:mensagem_falhou, **event_base(message_log, origem),
                         motivo: MOTIVOS.find { |klass, _| error.is_a?(klass) }&.last || "erro_wa", vai_retentar: retrying)
  end

  def self.track_sent(message_log, origem:, mentions: 0, attempt: 1)
    base = event_base(message_log, origem)
    AnalyticsEvent.track(:mensagem_enviada, **base, abre_rodada: message_log.opens_round, abre_cobranca: message_log.opens_billing,
                                            mencoes: mentions, tentativa: attempt)
    return unless message_log.opens_round

    group = WhatsappGroup.find_by(id: base[:whatsapp_group_id])
    rule = group&.rule("attendance")
    AnalyticsEvent.track(:rodada_aberta, rodada_id: message_log.id, whatsapp_group_id: base[:whatsapp_group_id],
                                         membros_cobrados: rule ? group.members_of(Attendance.tracked_keys(rule)).size : 0)
  end

  def self.event_base(message_log, origem)
    { message_log_id: message_log.id, flow_id: message_log.flow_id, whatsapp_group_id: message_log.whatsapp_group_id, origem: origem }
  end

  private

  # Número desta tentativa (1 = primeira). ponytail: contador no Redis por 1 dia, porque o Sidekiq só expõe
  # o retry_count num middleware de servidor.
  def next_attempt(message_log_id)
    key = "deliver:attempt:#{message_log_id}"
    Sidekiq.redis { |redis| redis.call("INCR", key).tap { redis.call("EXPIRE", key, 1.day.to_i) } }
  end
end
