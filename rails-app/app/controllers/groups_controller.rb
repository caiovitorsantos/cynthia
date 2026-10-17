class GroupsController < ApplicationController
  def index
    @groups = WhatsappGroup.order(:name)
  end

  def show
    @group = WhatsappGroup.find(params[:id])
    @participants = @group.group_participants.order(:name)
  end

  def update
    group = WhatsappGroup.find(params[:id])
    participants_params = params.fetch(:participants, {}).permit!.to_h

    GroupParticipant.transaction do
      group.group_participants.where(id: participants_params.keys).find_each do |participant|
        participant.update!(participants_params[participant.id.to_s].slice("role", "display_name"))
      end
    end

    redirect_to group_path(group), notice: "Membros atualizados."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to group_path(group), alert: "Erro ao salvar: #{e.message}"
  end

  def leave
    group = WhatsappGroup.find(params[:id])
    WaClient.leave_group(group.jid)
    group.destroy!
    redirect_to groups_path, notice: "Você saiu do grupo #{group.name}."
  rescue WaClient::NotConnected
    redirect_to group_path(group), alert: "WhatsApp não está conectado."
  rescue WaClient::Error, Faraday::ConnectionFailed, Faraday::TimeoutError => e
    redirect_to group_path(group), alert: "Erro ao sair do grupo: #{e.message}"
  end

  def destroy
    group = WhatsappGroup.find(params[:id])
    group.destroy!
    redirect_to groups_path, notice: "Grupo #{group.name} removido da lista."
  end

  def leave_selected
    ids = WhatsappGroup.where(id: params[:ids]).ids
    LeaveGroupsJob.perform_async(ids)
    redirect_to groups_path, notice: "Saindo de #{ids.size} grupo(s) em segundo plano, com intervalo entre cada um. Recarregue para acompanhar."
  end

  def destroy_selected
    removed = WhatsappGroup.where(id: params[:ids]).destroy_all.size
    redirect_to groups_path, notice: "#{removed} grupo(s) removido(s) da lista."
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
