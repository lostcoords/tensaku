Rails.application.routes.draw do
  root "pages#home"
  get "about", to: "pages#about"
  get "plain", to: "pages#plain"
  get "frames", to: "pages#frames"
  get "frames/lazy", to: "pages#lazy_frame", as: :lazy_frame
  get "guide", to: "pages#guide"
  get "signup", to: "pages#signup"
  post "signup", to: "pages#create_signup"
end
