# config/routes.rb

Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html
  resources :machines, only: %i[index]  # ←この行を追加！
  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Defines the root path route ("/")
  # root "posts#index" # ← 古いアプリのroot設定を使うので、これは不要

  # ===== ここから、古いアプリのroutes.rbの内容を移植 =====
  root 'router#index'

  get 'sign_in' => 'accounts#sign_in'
  post 'sign_in' => 'accounts#session_create', as: :create_account_session
  delete 'sign_out' => 'accounts#session_destroy'

  namespace :api, defaults: { format: :json } do
    namespace :v1 do
      resources :records, only: %i[show create update]
      resources :records, only: %i[index]
      resources :files, only: %i[show create]
      resources :machines, only: %i[index]
      resources :photos, only: %i[index]
      resources :router, only: %i[index] do
        member do
          get 'files'
          get 'layout'
        end
      end
    end
  end

  resources :photos, only: %i[] do
    member do
      get 'files'
      get 'layout'
    end
  end
  resources :records, only: %i[show create update]
  resources :records, only: %i[index]
  resources :files, only: %i[show create]

  # host 'sp.aizawa-k.com' do
  #   root 'bookmarks#create'
  # end

  resources :bookmarks, only: %i[show create], controller: :bookmarks
  resources :files, only: :index
  # ===== ここまで =====
end