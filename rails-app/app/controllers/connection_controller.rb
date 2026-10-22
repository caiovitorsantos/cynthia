class ConnectionController < ApplicationController
  def show
    fetch_status

    respond_to do |format|
      format.html
      format.turbo_stream
    end
  end

  def logout
    WaClient.logout
    redirect_to connection_path, notice: t(".notice")
  rescue WaClient::Error, Faraday::ConnectionFailed, Faraday::TimeoutError => e
    redirect_to connection_path, alert: t(".alert", error: e.message)
  end

  private

  def fetch_status
    @status = WaClient.status
    @qr = @status == "qr_pending" ? safe_qr_code : nil
  rescue Faraday::ConnectionFailed, Faraday::TimeoutError, WaClient::Error
    @status = "unreachable"
    @qr = nil
  end

  def safe_qr_code
    WaClient.qr_code
  rescue WaClient::Error
    nil
  end
end
