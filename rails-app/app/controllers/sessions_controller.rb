class SessionsController < ApplicationController
  skip_before_action :require_login, only: %i[new create]
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to login_path, alert: I18n.t("sessions.create.rate_limited") }

  def new
    redirect_to groups_path if logged_in?
  end

  def create
    if valid_credentials?(params[:username].to_s, params[:password].to_s)
      reset_session
      session[:admin] = true
      redirect_to groups_path
    else
      flash.now[:alert] = t(".alert")
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    reset_session
    redirect_to login_path, notice: t(".notice")
  end

  private

  def valid_credentials?(username, password)
    # Avalia os dois sempre (sem curto-circuito) para não vazar qual campo errou pelo tempo de resposta.
    [
      ActiveSupport::SecurityUtils.secure_compare(username, ENV.fetch("ADMIN_USERNAME", "admin")),
      ActiveSupport::SecurityUtils.secure_compare(password, ENV.fetch("ADMIN_PASSWORD"))
    ].all?
  end
end
