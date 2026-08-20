class WaClient
  Error = Class.new(StandardError)
  NotConnected = Class.new(Error)

  TIMEOUT = 15

  class << self
    def send_message(group_jid:, message:)
      handle(connection.post("/send", { group_jid: group_jid, message: message }))
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
