# Troca o idioma do painel e volta para a página de onde veio.
class LocalesController < ApplicationController
  skip_before_action :require_login

  def update
    cookies.permanent[:locale] = params[:locale] if WhatsappGroup::LOCALES.include?(params[:locale])
    redirect_back fallback_location: root_path
  end
end
