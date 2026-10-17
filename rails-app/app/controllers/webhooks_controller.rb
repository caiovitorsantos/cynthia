# Eventos do wa-service (reações e respostas em grupos), repassados às regras do grupo.
# Autenticado pelo INTERNAL_API_TOKEN.
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

    group&.group_rules&.each { |rule| rule.handler.handle_event(rule, event) }
    head :no_content
  end

  private

  def authenticate
    expected = ENV["INTERNAL_API_TOKEN"].to_s
    provided = request.headers["Authorization"].to_s

    head :unauthorized unless expected.present? && ActiveSupport::SecurityUtils.secure_compare(provided, expected)
  end
end
