class SendGuard
  ThrottledError = Class.new(StandardError)
  DailyCapReachedError = Class.new(StandardError)
  DuplicateMessageError = Class.new(StandardError)

  MAX_DAILY_SENDS = 50
  THROTTLE_WINDOW = 20 # segundos
  DUPLICATE_WINDOW = 6.hours
  THROTTLE_KEY = "wa_scheduler:send_throttle"

  class << self
    # Levanta um erro especifico se o envio nao puder acontecer agora.
    # Ordem: cap diario -> duplicidade -> throttle (o throttle e o
    # ultimo porque so deve consumir a janela se o envio realmente vai ocorrer).
    def check!(group_jid:, message:)
      check_daily_cap!
      check_duplicate!(group_jid, message)
      acquire_throttle!
    end

    private

    def check_daily_cap!
      count = MessageLog.where(status: "sent", sent_at: Date.current.all_day).count
      return if count < MAX_DAILY_SENDS

      raise DailyCapReachedError, "limite diário de #{MAX_DAILY_SENDS} envios atingido"
    end

    def check_duplicate!(group_jid, message)
      duplicate = MessageLog
        .where(status: "sent", group_jid: group_jid, rendered_body: message)
        .where("sent_at >= ?", DUPLICATE_WINDOW.ago)
        .exists?

      return unless duplicate

      raise DuplicateMessageError, "mensagem idêntica já enviada a este grupo nas últimas #{DUPLICATE_WINDOW.inspect}"
    end

    def acquire_throttle!
      acquired = Sidekiq.redis do |conn|
        conn.call("SET", THROTTLE_KEY, Time.current.to_i.to_s, "NX", "EX", THROTTLE_WINDOW.to_s)
      end

      return if acquired == "OK"

      raise ThrottledError, "aguardando janela de #{THROTTLE_WINDOW}s entre envios"
    end
  end
end
