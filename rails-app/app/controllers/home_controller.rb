# Página de apresentação para quem não está logado; quem está logado vai direto aos grupos.
class HomeController < ApplicationController
  skip_before_action :require_login

  def show
    redirect_to groups_path if logged_in?
  end
end
