Rails.application.routes.draw do
  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  root "connection#show"

  get "login" => "sessions#new"
  post "login" => "sessions#create"
  delete "logout" => "sessions#destroy"

  post "webhooks/whatsapp" => "webhooks#whatsapp"

  resource :connection, only: [ :show ], controller: "connection" do
    post :logout
  end

  resources :groups, only: [ :index, :show, :update, :destroy ] do
    resources :rules, only: [ :create, :update, :destroy ], controller: "group_rules"
    resources :templates, only: [ :new, :create, :edit, :update, :destroy ]
    resources :charges, only: [ :update ]
    resources :flows, only: [ :new, :create, :edit, :update, :destroy ] do
      member do
        post :run
      end
      collection do
        get :cron_preview
      end
    end
    member do
      post :leave
      patch :variables
      patch :lists
    end
    collection do
      post :sync
      post :leave_selected
      post :destroy_selected
    end
  end

  resources :logs, only: [ :index ] do
    member do
      post :resend
    end
  end
end
