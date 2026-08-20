class WaClient
  Error = Class.new(StandardError)
  NotConnected = Class.new(Error)

  TIMEOUT = 15
  # /send inclui delay humano proposital no wa-service (até ~14s: 2s de
  # presença + até 12s aleatório), então precisa de folga acima do timeout padrão.
  SEND_TIMEOUT = 30

  class << self
    def send_message(group_jid:, message:)
      response = connection.post("/send", { group_jid: group_jid, message: message }) do |req|
        req.options.timeout = SEND_TIMEOUT
        req.options.open_timeout = SEND_TIMEOUT
      end
      handle(response)
    end

    def groups
      handle(connection.get("/groups"))
    end

    def status
      handle(connection.get("/health"))["status"]
    end

    def qr_code
      handle(connection.get("/qr"))["qr"]
    end

    def logout
      handle(connection.post("/logout"))
    end

    private

    def connection
      Faraday.new(url: ENV.fetch("WA_SERVICE_URL")) do |f|
        f.request :json
        f.response :json
        f.headers["Authorization"] = ENV["INTERNAL_API_TOKEN"]
        f.options.timeout = TIMEOUT
        f.options.open_timeout = TIMEOUT
        f.adapter Faraday.default_adapter
      end
    end

    def handle(response)
      raise NotConnected, "wa-service não está conectado" if response.status == 503
      raise Error, "wa-service respondeu #{response.status}: #{response.body}" unless response.success?

      response.body
    end
  end
end
