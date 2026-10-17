# Eventos do wa-service (reações e respostas em grupos). Autenticado pelo INTERNAL_API_TOKEN.
class WebhooksController < ActionController::API
  before_action :authenticate

  def whatsapp
    AttendanceRecorder.call(
      kind: params.require(:kind),
      message_id: params.require(:message_id),
      participant_jid: params.require(:participant_jid),
      push_name: params[:push_name],
      text: params[:text].to_s
    )
    head :no_content
  end

  private

  def authenticate
    expected = ENV["INTERNAL_API_TOKEN"].to_s
    provided = request.headers["Authorization"].to_s

    head :unauthorized unless expected.present? && ActiveSupport::SecurityUtils.secure_compare(provided, expected)
  end
end
