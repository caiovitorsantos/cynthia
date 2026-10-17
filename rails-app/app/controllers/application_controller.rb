class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  # Admin single-user, self-hosted: login por sessão com as credenciais do .env.
  before_action :require_login
  helper_method :logged_in?

  private

  def logged_in?
    session[:admin] == true
  end

  def require_login
    redirect_to login_path unless logged_in?
  end
end
