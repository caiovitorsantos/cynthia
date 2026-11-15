# Marca ou desfaz o pagamento de uma cobrança pelo painel.
class ChargesController < ApplicationController
  def update
    group = WhatsappGroup.find(params[:group_id])
    charge = Billing::Charge.where(whatsapp_group: group).find(params[:id])
    was_paid = charge.paid?
    charge.update!(paid_at: was_paid ? nil : Time.current)
    if was_paid
      AnalyticsEvent.track(:cobranca_desmarcada, **charge.event_properties)
    else
      AnalyticsEvent.track(:cobranca_paga, **charge.event_properties, tipo: charge.kind, origem: "painel")
    end
    redirect_to group_path(group, tab: "regras", anchor: "regras")
  end
end
