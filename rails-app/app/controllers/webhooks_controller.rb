# Eventos do wa-service: comandos disparam os fluxos de comando do grupo (os que mexem em dados só
# para admins), menções à Cynth.ia viram resposta dela no grupo, e reações, respostas e listas
# coladas vão para as regras do grupo. Autenticado pelo INTERNAL_API_TOKEN.
class WebhooksController < ActionController::API
  before_action :authenticate

  SESSION_EVENTS = %w[sessao_conectada sessao_caiu].freeze

  def whatsapp
    return track_session if params[:kind] == "session"

    group = WhatsappGroup.find_by(jid: params.require(:group_jid))
    event = {
      kind: params.require(:kind),
      message_id: params.require(:message_id),
      participant_jid: params[:participant_jid].to_s,
      push_name: params[:push_name],
      text: params[:text].to_s
    }
    from_me = params[:from_me] == true
    route_event(group, event, from_me: from_me) if group
    head :no_content
  end

  private

  def route_event(group, event, from_me: false)
    case event[:kind]
    when "command" then run_commands(group, event, from_me: from_me)
    when "mention" then GroupAssistantJob.perform_async(group.id, event.stringify_keys)
    else
      return if event[:kind] == "reply" && AssistantAction.confirm_from_group_reply(group, event)

      group.group_rules.each { |rule| rule.handler.handle_event(rule, event) }
    end
  end

  def run_commands(group, event, from_me:)
    # O próprio número conectado (o dono) conta como admin, mas só com from_me explícito do wa-service:
    # participante vazio sozinho não basta (S-07, T18).
    admin = from_me || (event[:participant_jid].present? && group.group_participants.find_by(jid: event[:participant_jid])&.admin?)
    context = { "sender_jid" => event[:participant_jid], "push_name" => event[:push_name], "text" => event[:text], "origem" => "comando" }
    group.flows.for_command(event[:text]).each do |flow|
      next RunFlowJob.perform_async(flow.id, context) if admin || !flow.modifies_group?

      denied = MessageLog.create!(group_jid: group.jid, status: "pending",
                                  rendered_body: I18n.t("assistant.group.admins_only", locale: group.locale, command: flow.command))
      DeliverMessageJob.perform_async(denied.id, [])
    end
  end

  # Quedas e voltas da sessão do WhatsApp (tracking-plan, M4). Só os dois eventos e as três propriedades numéricas.
  def track_session
    name = params.require(:event)
    return head :unprocessable_entity unless SESSION_EVENTS.include?(name)

    properties = { apos_queda_s: params[:apos_queda_s], codigo: params[:codigo], logout: params[:logout] }
      .select { |key, value| value.is_a?(Integer) || (key == :logout && [ true, false ].include?(value)) }
    AnalyticsEvent.track(name, **properties)
    head :no_content
  end

  def authenticate
    expected = ENV["INTERNAL_API_TOKEN"].to_s
    provided = request.headers["Authorization"].to_s

    head :unauthorized unless expected.present? && ActiveSupport::SecurityUtils.secure_compare(provided, expected)
  end
end
