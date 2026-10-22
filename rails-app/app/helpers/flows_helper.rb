module FlowsHelper
  # Fugit::Cron#rough_frequency devolve segundos brutos (ex: 86400), não texto.
  def rough_frequency_in_words(seconds)
    case seconds
    when 0...3_600 then t("flows.frequency.minutes", count: seconds / 60)
    when 3_600...86_400 then t("flows.frequency.hours", count: seconds / 3_600)
    else t("flows.frequency.days", count: seconds / 86_400)
    end
  end

  # Cron dos formatos que o seletor de horário gera: { mode: "daily"/"weekly"/"monthly",
  # time: "14:00", weekdays: [2], monthday: 1 }. Qualquer outro formato devolve nil (avançado).
  def simple_cron(expression)
    minute, hour, monthday, month, weekday = expression.to_s.split
    return unless minute&.match?(/\A\d{1,2}\z/) && hour&.match?(/\A\d{1,2}\z/) && month == "*" && weekday

    time = format("%02d:%02d", hour.to_i, minute.to_i)
    if monthday == "*" && weekday == "*"
      { mode: "daily", time: time }
    elsif monthday == "*" && weekday.match?(/\A[0-6](,[0-6])*\z|\A[0-6]-[0-6]\z/)
      days = weekday.include?("-") ? Range.new(*weekday.split("-").map(&:to_i)).to_a : weekday.split(",").map(&:to_i)
      { mode: "weekly", time: time, weekdays: days }
    elsif weekday == "*" && monthday.match?(/\A\d{1,2}\z/)
      { mode: "monthly", time: time, monthday: monthday.to_i }
    end
  end

  # "toda terça às 14:00", "seg, qua e sex às 9:00", "todo dia 1 do mês às 9:00"; senão a frequência aproximada.
  def cron_in_words(expression)
    cron = simple_cron(expression)
    return rough_frequency_in_words(Fugit.parse_cron(expression).rough_frequency) unless cron

    case cron[:mode]
    when "daily" then t("flows.when.daily", time: cron[:time])
    when "monthly" then t("flows.when.monthly", day: cron[:monthday], time: cron[:time])
    else
      days = cron[:weekdays]
      label = if days == (1..5).to_a then t("flows.when.weekdays")
      elsif days.one? then t("flows.when.every")[days.first]
      else days.map { |day| t("date.abbr_day_names")[day].downcase }.to_sentence
      end
      t("flows.when.weekly", days: label, time: cron[:time])
    end
  end
end
