# Confirma ou cancela uma ação proposta pela Cynth.ia no chat.
class AssistantActionsController < ApplicationController
  before_action :set_action

  def confirm
    @action.confirm!
    render_card
  end

  def cancel
    @action.cancel!
    render_card
  end

  private

  def set_action
    @action = AssistantAction.find(params[:id])
  end

  def render_card
    render turbo_stream: turbo_stream.replace(@action, partial: "assistant/action", locals: { action: @action })
  end
end
