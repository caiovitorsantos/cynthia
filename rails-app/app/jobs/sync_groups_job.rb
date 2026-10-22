class SyncGroupsJob
  include Sidekiq::Job

  def perform
    WaClient.groups.each { |group| sync_group(group) }
  end

  private

  def sync_group(group)
    wa_group = WhatsappGroup.find_or_initialize_by(jid: group["jid"])
    wa_group.update!(
      name: group["name"],
      participants_count: group["participants_count"],
      synced_at: Time.current
    )

    sync_participants(wa_group, group["participants"]) if group.key?("participants")
  end

  def sync_participants(wa_group, participants)
    rows = participants.map do |participant|
      {
        whatsapp_group_id: wa_group.id,
        jid: participant["jid"],
        phone_number: phone_number_from_jid(participant["jid"]),
        name: participant["name"],
        admin: participant["admin"] == true,
        synced_at: Time.current
      }
    end
    rows = rows.uniq { |row| row[:jid] }

    if rows.any?
      GroupParticipant.upsert_all(
        rows,
        unique_by: [ :whatsapp_group_id, :jid ],
        on_duplicate: Arel.sql(
          "name = COALESCE(EXCLUDED.name, group_participants.name), " \
          "phone_number = EXCLUDED.phone_number, admin = EXCLUDED.admin, synced_at = EXCLUDED.synced_at, " \
          "updated_at = EXCLUDED.updated_at"
        )
      )
    end
    wa_group.group_participants.where.not(jid: rows.map { |row| row[:jid] }).delete_all
  end

  def phone_number_from_jid(jid)
    jid.to_s.split("@").first&.split(":")&.first
  end
end
