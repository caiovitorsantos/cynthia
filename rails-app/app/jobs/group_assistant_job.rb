# Marcaram a Cynth.ia numa mensagem do grupo: ela responde ali mesmo, marcando quem perguntou.
# Propostas (só de admins) vão com a prévia completa e esperam um admin responder "sim".
class GroupAssistantJob
  include Sidekiq::Job

  # Sem retry: repetir uma resposta no grupo é pior do que não responder.
  sidekiq_options retry: false

  # ponytail: teto simples por grupo e por hora no Redis; por pessoa se alguém abusar.
  HOURLY_LIMIT = 20

  def perform(group_id, event)
    group = WhatsappGroup.find(group_id)
    return unless CynthiaAssistant.available? && within_limit?(group)

    sender = group.participant_for!(event["participant_jid"], event["push_name"])
    text, actions = CynthiaAssistant.new.reply_in_group(group, sender: sender, text: event["text"].to_s)

    body = I18n.with_locale(group.locale) do
      parts = [ "@#{sender.phone_number} #{text}".strip ] + actions.map(&:preview)
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

  def within_limit?(group)
    key = "cynthia:group:#{group.id}:#{Time.current.strftime('%Y%m%d%H')}"
    count = Sidekiq.redis { |redis| redis.call("INCR", key).tap { redis.call("EXPIRE", key, 3600) } }
    count <= HOURLY_LIMIT
  end
end
