class SyncGroupsJob
  include Sidekiq::Job

  def perform
    WaClient.groups.each do |group|
      WhatsappGroup.upsert(
        {
          jid: group["jid"],
          name: group["name"],
          participants_count: group["participants_count"],
          synced_at: Time.current
        },
        unique_by: :jid
      )
    end
  end
end
