# Chat com a Cynth.ia no painel (canto da tela). A conversa é única para o admin.
class AssistantController < ApplicationController
  def show
    render layout: false
  end

  def create
    text = params[:text].to_s.strip
    if text.present? && CynthiaAssistant.available?
      group = WhatsappGroup.find_by(id: params[:group_id])
      begin
        CynthiaAssistant.new.reply(text, group: group)
      rescue CynthiaAssistant::Error => e
        @error = e.message
      end
    end
    render_conversation
  end

  # Nova conversa: apaga o histórico e descarta propostas não confirmadas.
  def destroy
    AssistantAction.panel.where(status: "pending").find_each(&:cancel!)
    AssistantMessage.delete_all
    AssistantAction.panel.update_all(reported: true)
    render_conversation
  end

  private

  def render_conversation
    render turbo_stream: turbo_stream.update("assistant_conversation", partial: "assistant/conversation", locals: { error: @error })
  end
end
