class PagesController < ApplicationController
  User = Data.define(:name)
  Message = Data.define(:subject, :sender)

  def landing
    # The same data script/demo_data.rb records the demo with.
    @user = User.new("Ada")
    @messages = [ Message.new("Lunch on Friday?", "Grace"), Message.new("Draft of the talk", "Linus"), Message.new("Your invoice", "Billing") ]
    render layout: "landing"
  end

  def show
    @page = Docs.page(params[:page]) or raise ActionController::RoutingError, "No page #{params[:page]}"
    render "pages/#{@page.slug}"
  end

  def not_found
    @page = Docs::Page.new("404", "Not found", nil)
    render status: :not_found
  end
end
