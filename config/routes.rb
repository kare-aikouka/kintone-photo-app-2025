Rails.application.routes.draw do
  resources :machines, only: %i[index]
  resources :machines, only: [:index, :show]
  get 'router' => 'router#index'

  get 'sign_in' => 'accounts#sign_in'
  post 'sign_in' => 'accounts#session_create', as: :create_account_session
  delete 'sign_out' => 'accounts#session_destroy'

  namespace :api, defaults: { format: 'json' } do
    namespace :v1 do
      resource :record, only: %i[show create update]
      resources :records, only: %i[index]
      resource :file, only: %i[show create]
      namespace :app do
        resource :form, only: %i[] do
          member do
            get 'fields'
            get 'layout'
          end
        end
      end

      resources :guest, only: %i[] do
        resource :record, only: %i[show create update]
        resources :records, only: %i[index]
        resource :file, only: %i[show create]
        namespace :app do
          resource :form, only: %i[] do
            member do
              get 'fields'
              get 'layout'
            end
          end
        end
      end
    end
  end

  resource :bookmark, only: %i[show create], controller: :bookmarks
  resources :files, only: :index

  root to: 'bookmarks#create'
end
