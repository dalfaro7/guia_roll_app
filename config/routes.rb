Rails.application.routes.draw do
 
  devise_for :users
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html
  resources :guides
  root "dashboard#index"
  get "dashboard", to: "dashboard#index"


resources :work_days do
  member do
    patch :generate_roles
    post :publish
    post :unpublish
    post :reset_roll
    patch :update_availability
    patch :update_roles
    delete :delete_with_reset 
  end
end

resources :guide_days, only: [:update]


  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  # root "posts#index"

end
