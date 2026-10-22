class GroupRulesController < ApplicationController
  before_action :set_group

  def create
    rule = @group.group_rules.new(kind: params.require(:kind))

    if rule.save
      redirect_to group_path(@group, anchor: "regras"), notice: "Regra \"#{rule.name}\" ativada."
    else
      redirect_to group_path(@group, anchor: "regras"), alert: "Erro ao ativar regra: #{rule.errors.full_messages.to_sentence}"
    end
  end

  def update
    rule = @group.group_rules.find(params[:id])
    rule.update!(settings: rule.settings.merge(rule.handler.settings_from(params.require(:rule))))
    redirect_to group_path(@group, anchor: "regras"), notice: "Regra \"#{rule.name}\" atualizada."
  end

  def destroy
    rule = @group.group_rules.find(params[:id])
    rule.destroy!
    redirect_to group_path(@group, anchor: "regras"), notice: "Regra \"#{rule.name}\" desativada."
  end

  private

  def set_group
    @group = WhatsappGroup.find(params[:group_id])
  end
end
