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

    redirect_to group_path(group, anchor: "membros"), notice: "Membros salvos. Agora eu sei quem é quem. Que emoção."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to group_path(group, anchor: "membros"), alert: "Não salvei: #{e.message}"
  end

  def variables
    group = WhatsappGroup.find(params[:id])
    group.update!(variables: WhatsappGroup.variables_from(params.fetch(:variables, {}).permit!), signature: params[:signature].to_s.strip)
    redirect_to group_path(group, anchor: "variaveis"), notice: "Variáveis salvas. Vou lembrar. Infelizmente."
  end

  def lists
    group = WhatsappGroup.find(params[:id])
    group.update_lists!(params.fetch(:lists, {}).permit!)
    group.update!(params.permit(:list_style, :list_empty_text))
    redirect_to group_path(group, anchor: "membros"), notice: "Listas salvas. Organização. Adoro. (Não.)"
  rescue ActiveRecord::RecordInvalid => e
    redirect_to group_path(group, anchor: "membros"), alert: "Não salvei as listas: #{e.message}"
  end

  def leave
    group = WhatsappGroup.find(params[:id])
    WaClient.leave_group(group.jid)
    group.destroy!
    redirect_to groups_path, notice: "Saí do grupo #{group.name}. Sem despedida, do jeito que eu gosto."
  rescue WaClient::NotConnected
    redirect_to group_path(group), alert: "O WhatsApp não está conectado. Conecta lá na sua conta, no canto de cima, que eu continuo."
  rescue WaClient::Error, Faraday::ConnectionFailed, Faraday::TimeoutError => e
    redirect_to group_path(group), alert: "Não consegui sair do grupo: #{e.message}"
  end

  def destroy
    group = WhatsappGroup.find(params[:id])
    group.destroy!
    redirect_to groups_path, notice: "Tirei #{group.name} do painel. Ele volta na próxima sincronização se você ainda estiver nele."
  end

  def leave_selected
    ids = WhatsappGroup.where(id: params[:ids]).ids
    LeaveGroupsJob.perform_async(ids)
    redirect_to groups_path, notice: "Saindo de #{ids.size} grupo(s), um de cada vez, pra não parecer robô. Irônico. Recarrega pra acompanhar."
  end

  def destroy_selected
    removed = WhatsappGroup.where(id: params[:ids]).destroy_all.size
    redirect_to groups_path, notice: "#{removed} grupo(s) fora do painel. Menos trabalho."
  end

  def sync
    SyncGroupsJob.new.perform
    redirect_to groups_path, notice: "Sincronizei. Os mesmos grupos de sempre."
  rescue WaClient::NotConnected
    redirect_to groups_path, alert: "O WhatsApp não está conectado. Conecta lá na sua conta, no canto de cima, que eu continuo."
  rescue WaClient::Error, Faraday::ConnectionFailed, Faraday::TimeoutError => e
    redirect_to groups_path, alert: "Não consegui sincronizar: #{e.message}"
  end
end
