Rails.application.routes.draw do
  root "pages#show", page: "index"

  Docs::PAGES.each do |page|
    get page.slug, to: "pages#show", page: page.slug, as: "#{page.slug.tr("-", "_")}_page" unless page.slug == "index"
  end

  get "404", to: "pages#not_found"
end
