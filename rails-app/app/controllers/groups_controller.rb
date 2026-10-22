class GroupsController < ApplicationController
  def index
    # Grupos configurados (com fluxos ou regras) primeiro.
    @groups = WhatsappGroup.includes(:group_rules).left_joins(:flows).group(:id)
      .select("whatsapp_groups.*, COUNT(flows.id) AS flows_count").to_a
      .sort_by { |group| [ group.flows_count.zero? && group.group_rules.empty? ? 1 : 0, group.name.to_s.downcase ] }
  end

  def show
    @group = WhatsappGroup.includes(:member_lists, :group_rules).find(params[:id])
    @participants = @group.group_participants.includes(:member_lists).order(:name)
    @templates = @group.templates.order(:name)
    @flows = @group.flows.order(:trigger, :name)
    @attendance_rule = @group.rule("attendance")
    if @attendance_rule
      @attendance_settings = Attendance.settings(@attendance_rule)
      @round = Attendance.current_round(@attendance_rule)
      @statuses = Attendance.statuses(@attendance_rule)
    end
  end

  # Membros: nome na lista e listas de cada um.
  def update
    group = WhatsappGroup.find(params[:id])
    participants_params = params.fetch(:participants, {}).permit!.to_h

    GroupParticipant.transaction do
      group.group_participants.where(id: participants_params.keys).find_each do |participant|
        attributes = participants_params[participant.id.to_s]
        participant.update!(display_name: attributes["display_name"], member_list_ids: group.member_lists.where(id: attributes["member_list_ids"]).ids)
      end
    end

    redirect_to group_path(group, anchor: "membros"), notice: "Membros atualizados."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to group_path(group, anchor: "membros"), alert: "Erro ao salvar: #{e.message}"
  end

  def variables
    group = WhatsappGroup.find(params[:id])
    group.update!(variables: WhatsappGroup.variables_from(params.fetch(:variables, {}).permit!), signature: params[:signature].to_s.strip)
    redirect_to group_path(group, anchor: "variaveis"), notice: "Variáveis do grupo atualizadas."
  end

  def lists
    group = WhatsappGroup.find(params[:id])
    group.update_lists!(params.fetch(:lists, {}).permit!)
    group.update!(params.permit(:list_style, :list_empty_text))
    redirect_to group_path(group, anchor: "membros"), notice: "Listas atualizadas."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to group_path(group, anchor: "membros"), alert: "Erro ao salvar listas: #{e.message}"
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
