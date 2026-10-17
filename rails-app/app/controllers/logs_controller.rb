class LogsController < ApplicationController
  PER_PAGE = 25

  def index
    @status = params[:status].presence
    scope = MessageLog.order(created_at: :desc)
    scope = scope.where(status: @status) if @status.present?

    @page = params[:page].presence&.to_i || 1
    @total_pages = (scope.count / PER_PAGE.to_f).ceil
    @logs = scope.limit(PER_PAGE).offset((@page - 1) * PER_PAGE)
  end

  def resend
    log = MessageLog.find(params[:id])
    new_log = MessageLog.create!(
      schedule: log.schedule, group_jid: log.group_jid,
      rendered_body: log.rendered_body, status: "pending"
    )

    SendGuard.check!(group_jid: log.group_jid, message: log.rendered_body)
    response = WaClient.send_message(group_jid: log.group_jid, message: log.rendered_body)
    new_log.mark_sent!(response.try(:[], "message_id"))
    redirect_to logs_path, notice: "Reenviado com sucesso."
  rescue WaClient::NotConnected, SendGuard::DailyCapReachedError,
         SendGuard::DuplicateMessageError, SendGuard::ThrottledError, WaClient::Error => e
    new_log.update!(status: "failed", error_message: e.message)
    redirect_to logs_path, alert: "Falha ao reenviar: #{e.message}"
  end
end
