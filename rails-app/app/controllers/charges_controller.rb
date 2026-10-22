# Marca ou desfaz o pagamento de uma cobrança pelo painel.
class ChargesController < ApplicationController
  def update
    group = WhatsappGroup.find(params[:group_id])
    charge = Billing::Charge.where(whatsapp_group: group).find(params[:id])
    charge.update!(paid_at: charge.paid? ? nil : Time.current)
    redirect_to group_path(group, anchor: "regras")
  end
end
