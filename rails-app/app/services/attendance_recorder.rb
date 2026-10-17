# Registra presença a partir de uma reação ou resposta numa lista de presença.
class AttendanceRecorder
  CONFIRM = %w[✅ ✔ ☑ 👍].freeze
  DECLINE = %w[❌ ✖ ❎ 👎].freeze

  def self.call(kind:, message_id:, participant_jid:, push_name: nil, text: "")
    round = MessageLog.find_by(wa_message_id: message_id)&.attendance_round
    return unless round

    group = WhatsappGroup.find_by(jid: round.group_jid)
    return unless group

    text = text.to_s.strip

    # Reação removida: apaga a resposta.
    if kind == "reaction" && text.empty?
      participant = group.group_participants.find_by(jid: participant_jid)
      round.attendances.where(group_participant: participant).destroy_all if participant
      return
    end

    status = status_for(text)
    return unless status

    participant = group.group_participants.find_or_create_by!(jid: participant_jid) do |new_participant|
      new_participant.name = push_name.presence
      new_participant.phone_number = participant_jid.split("@").first.split(":").first
    end

    round.attendances.find_or_initialize_by(group_participant: participant).update!(status: status)
  end

  def self.status_for(text)
    if CONFIRM.any? { |emoji| text.start_with?(emoji) } then "confirmed"
    elsif DECLINE.any? { |emoji| text.start_with?(emoji) } then "declined"
    end
  end
end
