module FlowsHelper
  # Fugit::Cron#rough_frequency devolve segundos brutos (ex: 86400), não texto.
  def rough_frequency_in_words(seconds)
    case seconds
    when 0...3_600
      minutes = seconds / 60
      "a cada #{pluralize(minutes, 'minuto', plural: 'minutos')}"
    when 3_600...86_400
      hours = seconds / 3_600
      "a cada #{pluralize(hours, 'hora', plural: 'horas')}"
    else
      days = seconds / 86_400
      "a cada #{pluralize(days, 'dia', plural: 'dias')}"
    end
  end
end
