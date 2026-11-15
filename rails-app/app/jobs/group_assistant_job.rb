# Marcaram a Cynth.ia numa mensagem do grupo: ela responde ali mesmo, marcando quem perguntou.
# Propostas (só de admins) vão com a prévia completa e esperam um admin responder "sim".
# Antes da primeira chamada à Anthropic com dados do grupo, sai o aviso único de IA de terceiro (RF-28).
class GroupAssistantJob
  include Sidekiq::Job

  # Sem retry: repetir uma resposta no grupo é pior do que não responder.
  sidekiq_options retry: false

  # Tetos (T6, WHA-14). A cota do SendGuard é 50 envios/dia para tudo; a Cynth.ia fica com no máximo
  # DAILY_LIMIT deles (aviso incluído), sobrando 35 para rotinas e lembretes. Quem passa do teto: silêncio.
  PERSON_HOURLY_LIMIT = 3   # por pessoa, por grupo, por hora
  HOURLY_LIMIT = 20         # por grupo, por hora
  DAILY_LIMIT = 15          # todas as respostas da Cynth.ia no dia, todos os grupos

  def perform(group_id, event)
    group = WhatsappGroup.find(group_id)
    jid = event["participant_jid"].to_s
    return if jid.blank? || !CynthiaAssistant.available? || !within_limits?(group, jid)
    return unless ai_notice_delivered?(group)

    sender = group.participant_for!(jid, event["push_name"])
    text, actions = CynthiaAssistant.new.reply_in_group(group, sender: sender, text: event["text"].to_s)

    body = I18n.with_locale(group.locale) do
      parts = [ "@#{sender.phone_number} #{fill_variables(group, text)}".strip ] + actions.map(&:preview)
      parts << I18n.t("assistant.group.confirm_hint") if actions.any?
      parts.join("\n\n")
    end
    log = MessageLog.create!(group_jid: group.jid, rendered_body: body, status: "pending")
    AssistantAction.where(id: actions.map(&:id)).update_all(message_log_id: log.id)
    DeliverMessageJob.perform_async(log.id, [ sender.jid ])
  rescue CynthiaAssistant::Error => e
    Rails.logger.warn("GroupAssistantJob: #{e.message}")
  end

  private

  # Pessoa primeiro: quem abusa não gasta o teto do grupo nem o do dia.
  def within_limits?(group, jid)
    hour = Time.current.strftime("%Y%m%d%H")
    within?("cynthia:person:#{group.id}:#{jid}:#{hour}", PERSON_HOURLY_LIMIT, 1.hour) &&
      within?("cynthia:group:#{group.id}:#{hour}", HOURLY_LIMIT, 1.hour) &&
      within?("cynthia:day:#{Date.current.strftime('%Y%m%d')}", DAILY_LIMIT, 1.day)
  end

  def within?(key, limit, ttl)
    Sidekiq.redis { |redis| redis.call("INCR", key).tap { redis.call("EXPIRE", key, ttl.to_i) } } <= limit
  end

  # RF-28: o aviso sai antes (envio síncrono, para só seguir se ele saiu). Falhou: não responde, e a próxima
  # menção tenta de novo. O lock evita dois avisos com menções simultâneas.
  def ai_notice_delivered?(group)
    return true if group.ai_notice_sent_at

    lock = "cynthia:notice:#{group.id}"
    return false unless Sidekiq.redis { |redis| redis.call("SET", lock, "1", "NX", "EX", "120") } == "OK"

    begin
      notice = MessageLog.create!(group_jid: group.jid, kind: MessageLog::AI_NOTICE, status: "pending",
                                  rendered_body: I18n.t("assistant.group.ai_notice", locale: group.locale))
      DeliverMessageJob.new.perform(notice.id)
      notice.reload.status == "sent"
    rescue SendGuard::ThrottledError, WaClient::Error => e
      Rails.logger.warn("GroupAssistantJob: aviso de IA não saiu: #{e.message}")
      false
    ensure
      Sidekiq.redis { |redis| redis.call("DEL", lock) }
    end
  end

  # RF-29: o modelo só conhece o nome da variável; o valor entra aqui, depois da Anthropic.
  def fill_variables(group, text)
    text.gsub(Template::VARIABLE_PATTERN) { |match| group.variables.fetch(Regexp.last_match(1), match) }
  end
end
