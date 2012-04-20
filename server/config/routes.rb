Server::Application.routes.draw do
  match 'files' => 'files#create'
  resources :clients
  resources :etch_configs
  resources :facts
  resources :originals
  resources :results
  
  root :to => 'dashboard#index'
  match 'chart' => 'dashboard#chart'
end
