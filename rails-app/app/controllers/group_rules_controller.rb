class GroupRulesController < ApplicationController
  before_action :set_group

  def create
    rule = @group.group_rules.new(kind: params.require(:kind))

    if rule.save
      redirect_to group_path(@group, anchor: "recursos"), notice: "Recurso \"#{rule.name}\" ativado."
    else
      redirect_to group_path(@group, anchor: "recursos"), alert: "Erro ao ativar recurso: #{rule.errors.full_messages.to_sentence}"
    end
  end

  def update
    rule = @group.group_rules.find(params[:id])
    rule.update!(settings: rule.settings.merge(rule.handler.settings_from(params.require(:rule))))
    redirect_to group_path(@group, anchor: "recursos"), notice: "Recurso \"#{rule.name}\" atualizado."
  end

  def destroy
    rule = @group.group_rules.find(params[:id])
    rule.destroy!
    redirect_to group_path(@group, anchor: "recursos"), notice: "Recurso \"#{rule.name}\" desativado."
  end

  private

  def set_group
    @group = WhatsappGroup.find(params[:group_id])
  end
end
