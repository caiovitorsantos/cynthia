# Eventos do wa-service: comandos disparam os fluxos de comando do grupo (os que mexem em dados só
# para admins), menções à Cynth.ia viram resposta dela no grupo, e reações, respostas e listas
# coladas vão para as regras do grupo. Autenticado pelo INTERNAL_API_TOKEN.
class WebhooksController < ActionController::API
  before_action :authenticate

  def whatsapp
    group = WhatsappGroup.find_by(jid: params.require(:group_jid))
    event = {
      kind: params.require(:kind),
      message_id: params.require(:message_id),
      participant_jid: params[:participant_jid].to_s,
      push_name: params[:push_name],
      text: params[:text].to_s
    }
    route_event(group, event) if group
    head :no_content
  end

  private

  def route_event(group, event)
    case event[:kind]
    when "command" then run_commands(group, event)
    when "mention" then GroupAssistantJob.perform_async(group.id, event.stringify_keys)
    else
      return if event[:kind] == "reply" && AssistantAction.confirm_from_group_reply(group, event)

      group.group_rules.each { |rule| rule.handler.handle_event(rule, event) }
    end
  end

  def run_commands(group, event)
    # Sem participante = o próprio número conectado (o dono), que conta como admin.
    admin = event[:participant_jid].blank? || group.group_participants.find_by(jid: event[:participant_jid])&.admin?
    context = { "sender_jid" => event[:participant_jid], "push_name" => event[:push_name], "text" => event[:text] }
    group.flows.for_command(event[:text]).each do |flow|
      next RunFlowJob.perform_async(flow.id, context) if admin || !flow.modifies_group?

      denied = MessageLog.create!(group_jid: group.jid, status: "pending",
                                  rendered_body: I18n.t("assistant.group.admins_only", locale: group.locale, command: flow.command))
      DeliverMessageJob.perform_async(denied.id, [])
    end
  end

  def authenticate
    expected = ENV["INTERNAL_API_TOKEN"].to_s
    provided = request.headers["Authorization"].to_s

    head :unauthorized unless expected.present? && ActiveSupport::SecurityUtils.secure_compare(provided, expected)
  end
end
