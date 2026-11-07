Rails.application.routes.draw do
  root "pages#landing"

  Docs::PAGES.each do |page|
    get page.slug, to: "pages#show", page: page.slug, as: "#{page.slug.tr("-", "_")}_page"
  end

  get "404", to: "pages#not_found"
end
