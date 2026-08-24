class GroupsController < ApplicationController
  def index
    @groups = WhatsappGroup.order(:name)
  end

  def show
    @group = WhatsappGroup.find(params[:id])
    @participants = @group.group_participants.order(:name)
  end

  def sync
    SyncGroupsJob.new.perform
    redirect_to groups_path, notice: "Grupos sincronizados."
  rescue WaClient::NotConnected
    redirect_to groups_path, alert: "WhatsApp não está conectado."
  rescue WaClient::Error, Faraday::ConnectionFailed, Faraday::TimeoutError => e
    redirect_to groups_path, alert: "Erro ao sincronizar: #{e.message}"
  end
end
