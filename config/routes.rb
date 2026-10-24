Rails.application.routes.draw do
  get 'kayaktalkie/password/new', to: 'kayaktalkie_passwords#new', as: :new_kayaktalkie_password
  post 'kayaktalkie/password', to: 'kayaktalkie_passwords#create', as: :kayaktalkie_password
  get 'kayaktalkie/password/edit', to: 'kayaktalkie_passwords#edit', as: :edit_kayaktalkie_password
  patch 'kayaktalkie/password', to: 'kayaktalkie_passwords#update'
  get 'kayaktalkie/profile', to: 'kayaktalkie_profiles#edit', as: :kayaktalkie_profile
  patch 'kayaktalkie/profile', to: 'kayaktalkie_profiles#update'
  get 'kayaktalkie/collaborators', to: 'kayaktalkie_collaborators#index', as: :kayaktalkie_collaborators
  post 'kayaktalkie/collaborators', to: 'kayaktalkie_collaborators#create'
  patch 'kayaktalkie/collaborators/:id', to: 'kayaktalkie_collaborators#update', as: :kayaktalkie_collaborator
  post "tracking/teams", to: "kayaktalkie_dashboard#create_team", as: :tracking_teams
  get 'kayaktalkie/login', to: 'kayaktalkie#new', as: :kayaktalkie_login
  post 'kayaktalkie/login', to: 'kayaktalkie#create'
  post 'kayaktalkie/logout', to: 'kayaktalkie#destroy', as: :kayaktalkie_logout
  get 'kayaktalkie', to: 'kayaktalkie#show', as: :kayaktalkie
  get 'api/account', to: 'tracking_api#account'
  get "api/map/voice", to: "tracking_api#map_voice"
  get 'api/voice/channels', to: 'voice#channels'
  post 'tracking/channels', to: 'kayaktalkie_dashboard#create_channel', as: :tracking_channels
  patch 'tracking/accounts/:id/channels', to: 'kayaktalkie_dashboard#update_channels', as: :tracking_account_channels
  get "tracking/voice", to: "kayaktalkie_dashboard#voice", as: :tracking_voice
  post "api/voice/join", to: "voice#join"
  get "api/voice/status", to: "voice#status"
  post "api/voice/claim", to: "voice#claim"
  post "api/voice/release", to: "voice#release"
  get "tracking", to: "kayaktalkie_dashboard#index", as: :tracking
  get "tracking/accounts", to: "kayaktalkie_dashboard#accounts", as: :tracking_accounts
  post "tracking/accounts", to: "kayaktalkie_dashboard#create_account"
  post "api/login", to: "tracking_api#login"
  post "api/logout", to: "tracking_api#logout"
  post "api/location", to: "tracking_api#location"
  post "api/map/area", to: "tracking_api#map_area"
  get "api/me", to: "tracking_api#me"
  get "api/users", to: "tracking_api#users"
  get "api/alerts", to: "tracking_api#alerts"
  post "api/alerts/ack", to: "tracking_api#ack"
  get "api/reports/speed", to: "tracking_api#report"

  get "webhooks/whatsapp", to: "whatsapp_webhooks#verify"
  post "webhooks/whatsapp", to: "whatsapp_webhooks#receive"
  post "webhooks/weather_reports",
       to: "weather_report_imports#create",
       as: :weather_report_import

  get "reportes-rio-balsa",
      to: "weather_reports#index",
      as: :weather_reports

  resource :whatsapp_test_message, only: [:new, :create] do
    post :check
  end

  get "audit_logs/index"
  get "bus_assignments/create"
  get "bus_assignments/destroy"
  get "buses/index"
  get "buses/show"
  get "buses/new"
  get "buses/edit"

  devise_for :users

  root "dashboard#index"
  get "dashboard", to: "dashboard#index"

  resources :guides do
    member do
      # Activa o desactiva un guía.
      # Al activar, Guide inicia automáticamente
      # un nuevo ciclo de fairness.
      patch :toggle_active
    end
  end

  resources :roll_notes, only: [:index, :create, :destroy]

  resources :work_days do
    member do
      patch :generate_roles

      post :publish
      post :unpublish
      post :reset_roll

      patch :update_availability
      patch :update_roles

      delete :delete_with_reset

      get :locations
      post :create_slots
      get :edit_slots

      post :force_assign
      get :preview_force_assign

      post :move_assigned_task_to_roll
    end
  end

  resources :location_slots do
    member do
      patch :update_skills
    end

    collection do
      patch :update_all
    end
  end

  resources :guide_days, only: [:update]

  get "guide_assignments",
      to: "guide_assignments#index"

  get "day_off_report",
      to: "day_off_report#index"

  post "assign_day_off",
       to: "day_off_report#assign_day_off"

  post "remove_day_off",
       to: "day_off_report#remove_day_off"

  resources :buses

  resources :bus_assignments,
            only: [:create, :destroy]

  resources :audit_logs,
            only: [:index]

  resources :office_holidays
  resources :office_overtimes

  resources :office_employee_days do
    collection do
      post :generate_month
    end
  end

  resources :office_day_credits,
            only: [:index, :new, :create, :destroy] do
    collection do
      post :generate_for_month
    end
  end

  resources :office_vacation_credits,
            only: [:index, :new, :create, :destroy]

  get "up" => "rails/health#show",
      as: :rails_health_check
end
