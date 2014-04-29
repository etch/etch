Rails.application.routes.draw do
  post 'files' => 'files#create'
  resources :clients
  resources :etch_configs
  resources :facts
  resources :originals
  resources :results
  
  root :to => 'dashboard#index'
  get 'chart/:chart' => 'dashboard#chart'
end
