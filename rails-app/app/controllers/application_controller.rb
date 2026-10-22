class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  # Admin single-user, self-hosted: login por sessão com as credenciais do .env.
  before_action :require_login
  around_action :switch_locale
  helper_method :logged_in?

  private

  def logged_in?
    session[:admin] == true
  end

  # Idioma do painel: o escolhido (cookie) ou o primeiro do navegador que a gente fala.
  def switch_locale(&action)
    I18n.with_locale(cookies[:locale].presence_in(WhatsappGroup::LOCALES) || browser_locale, &action)
  end

  def browser_locale
    request.headers["Accept-Language"].to_s.downcase.scan(/[a-z]{2}/).each do |language|
      locale = WhatsappGroup::LOCALES.find { |candidate| candidate.downcase.start_with?(language) }
      return locale if locale
    end
    I18n.default_locale
  end

  def require_login
    redirect_to login_path unless logged_in?
  end
end
