Rails.application.routes.draw do
  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  root "connection#show"

  resource :connection, only: [ :show ], controller: "connection" do
    post :logout
  end

  resources :templates

  resources :groups, only: [ :index, :show ] do
    collection do
      post :sync
    end
  end

  resources :schedules do
    member do
      post :send_test
    end
    collection do
      get :cron_preview
    end
  end

  resources :logs, only: [ :index ] do
    member do
      post :resend
    end
  end
end
