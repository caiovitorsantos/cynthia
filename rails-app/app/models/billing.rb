# Regra de grupo "Cobrança mensal" (ver GroupRule). Um passo "Enviar template" marcado
# "abre cobrança" abre a cobrança do mês anterior: uma mensalidade para cada membro das listas
# que pagam (charged_lists) e uma diária para cada dia em que um avulso confirmou presença numa
# rodada daquele mês (regra Lista de presença). Pagamentos são marcados com 💰 numa cópia
# colada da lista no grupo ou pelo painel; pago nunca volta sozinho, então cópias antigas não
# desfazem nada.
module Billing
  DEFAULTS = {
    "charged_lists" => [],
    "paid_emojis" => "💰 ✅"
  }.freeze

  VARIABLE_NAMES = %w[cobranca_mensais cobranca_avulsos pendentes_pagamento].freeze

  DATE_LINE = /\A\s*(\d{1,2})\/(\d{1,2})\s*\z/

  class << self
    def settings(rule)
      DEFAULTS.merge(rule.settings)
    end

    def settings_from(params)
      {
        "charged_lists" => Array(params[:charged_lists]).compact_blank,
        "paid_emojis" => params[:paid_emojis].to_s.strip
      }.select { |key, _| params.key?(key) }
    end

    def provides_variable?(_rule, key)
      VARIABLE_NAMES.include?(key)
    end

    def before_message(rule, step, now)
      open!(rule, now.prev_month.strftime("%Y-%m")) if step["opens_billing"] == "1"
    end

    def prepare_message(_rule, _message_log, _template) = nil

    # Cria as cobranças do mês (idempotente: rodar de novo só acrescenta o que faltar).
    def open!(rule, period)
      group = rule.whatsapp_group
      monthly = group.members_of(settings(rule)["charged_lists"])
      monthly.each { |participant| charges(group).find_or_create_by!(group_participant: participant, period: period, kind: "mensal") }

      month = Date.strptime(period, "%Y-%m")
      rounds = MessageLog.where(group_jid: group.jid, opens_round: true, status: "sent", sent_at: month.all_month)
      Attendance::Response.where(message_log: rounds, status: "confirmed").includes(:message_log).find_each do |response|
        next if monthly.any? { |participant| participant.id == response.group_participant_id }

        charges(group).find_or_create_by!(group_participant_id: response.group_participant_id, guest_name: response.guest_name,
                                          period: period, kind: "avulso", date: response.message_log.sent_at.to_date)
      end

      counts = charges(group).where(period: period).group(:kind).count
      AnalyticsEvent.track(:cobranca_aberta, whatsapp_group_id: group.id, periodo: period,
                                             mensalidades: counts["mensal"].to_i, diarias: counts["avulso"].to_i)
    end

    def current_period(rule)
      charges(rule.whatsapp_group).maximum(:period)
    end

    def current_charges(rule)
      charges(rule.whatsapp_group).where(period: current_period(rule)).includes(:group_participant)
        .sort_by { |charge| [ charge.date || Date.new(0), charge.label.to_s.downcase ] }
    end

    # { group_participant_id => mensalidades em aberto, contando todos os meses }
    def months_due(rule)
      charges(rule.whatsapp_group).unpaid.where(kind: "mensal").where.not(group_participant_id: nil).group(:group_participant_id).count
    end

    def render_variable(rule, key, mentioned_jids)
      return unless provides_variable?(rule, key)

      group = rule.whatsapp_group
      mark = settings(rule)["paid_emojis"].split.first
      all = current_charges(rule)

      case key
      when "cobranca_mensais"
        due = months_due(rule)
        group.format_list(all.select { |charge| charge.kind == "mensal" }.map do |charge|
          next "#{charge.label} #{mark}".strip if charge.paid?

          months = due[charge.group_participant_id].to_i
          [ mention(charge, mentioned_jids), ("#{months}x" if months > 1) ].compact.join(" ")
        end)
      when "cobranca_avulsos"
        days = all.select { |charge| charge.kind == "avulso" }.group_by(&:date)
        return group.list_empty_text if days.empty?

        days.map do |date, day_charges|
          lines = day_charges.map { |charge| charge.paid? ? "#{charge.label} #{mark}".strip : mention(charge, mentioned_jids) }
          [ date.strftime("%d/%m"), *lines ].join("\n")
        end.join("\n\n")
      when "pendentes_pagamento"
        all.reject(&:paid?).uniq { |charge| charge.group_participant_id || charge.guest_name }.map { |charge| mention(charge, mentioned_jids) }.join(" ")
      end
    end

    # Cópia colada da mensagem que abriu a cobrança: linhas com 💰 marcam pago. Linhas
    # numeradas são mensalidades; depois de uma linha de data ("02/09"), diárias daquele dia.
    def handle_event(rule, event)
      return unless event[:kind] == "list"

      group = rule.whatsapp_group
      opening = MessageLog.where(group_jid: group.jid, opens_billing: true, status: "sent").order(sent_at: :desc).first
      period = current_period(rule)
      lines = event[:text].to_s.lines.map(&:strip)
      header_index = lines.index(&:present?)
      return unless opening && period && header_index && header(opening.rendered_body) == WhatsappGroup.normalize_name(lines[header_index])

      paid = settings(rule)["paid_emojis"].split
      people = GroupParticipant.where(whatsapp_group_id: group.id).to_a
      month = Date.strptime(period, "%Y-%m")
      date = nil
      unmatched = []

      lines.drop(header_index + 1).each do |line|
        if (day = line.match(DATE_LINE))
          date = Date.new(month.year, day[2].to_i, day[1].to_i) if Date.valid_date?(month.year, day[2].to_i, day[1].to_i)
          next
        end

        content = line[Attendance::LIST_LINE, 1] || (line if date) # depois de uma data, cada linha é um avulso
        next unless content && paid.any? { |emoji| content.include?(emoji) }

        name = content.gsub(/[^\p{L}\p{N}\s.'@-]/, "").squish.sub(/\s+\d+x\z/i, "") # tira emojis e o "5x" de atraso
        charge = find_charge(group, period, date, name, people)

        if charge
          unless charge.paid?
            charge.update!(paid_at: Time.current)
            AnalyticsEvent.track(:cobranca_paga, **charge.event_properties, tipo: charge.kind, origem: "colagem")
          end
        else
          unmatched << name
        end
      end

      opening.update!(unmatched_names: (opening.unmatched_names + unmatched).uniq) if unmatched.any?
    end

    # Nomes com 💰 em listas coladas que não bateram com nenhuma cobrança.
    def unmatched_names(rule)
      group = rule.whatsapp_group
      opening = MessageLog.where(group_jid: group.jid, opens_billing: true, status: "sent").order(sent_at: :desc).first
      return [] unless opening

      people = GroupParticipant.where(whatsapp_group_id: group.id).to_a
      opening.unmatched_names.reject { |name| group.participant_named(name, people: people) }
    end

    private

    def charges(group)
      Charge.where(whatsapp_group: group)
    end

    def find_charge(group, period, date, name, people)
      scope = charges(group).where(period: period, kind: date ? "avulso" : "mensal", date: date)
      participant = group.participant_named(name, people: people)
      return scope.find_by(group_participant: participant) if participant

      key = WhatsappGroup.normalize_name(name)
      scope.where(group_participant_id: nil).find { |charge| WhatsappGroup.normalize_name(charge.guest_name) == key }
    end

    def header(body)
      WhatsappGroup.normalize_name(body.to_s.lines.find(&:present?))
    end

    def mention(charge, mentioned_jids)
      return charge.guest_name unless charge.group_participant

      mentioned_jids << charge.group_participant.jid
      "@#{charge.group_participant.phone_number}"
    end
  end
end
