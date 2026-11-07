class PagesController < ApplicationController
  def show
    @page = Docs.page(params[:page]) or raise ActionController::RoutingError, "No page #{params[:page]}"
    render "pages/#{@page.slug}"
  end

  def not_found
    @page = Docs::Page.new("404", "Not found", nil)
    render status: :not_found
  end
end
