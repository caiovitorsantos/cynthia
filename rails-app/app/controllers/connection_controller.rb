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
    redirect_to connection_path, notice: "Desconectei. Escaneia o QR de novo quando der vontade."
  rescue WaClient::Error, Faraday::ConnectionFailed, Faraday::TimeoutError => e
    redirect_to connection_path, alert: "Não consegui desconectar: #{e.message}. Clássico."
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
