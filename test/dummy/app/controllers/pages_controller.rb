class PagesController < ApplicationController
  Item = Struct.new(:name, :price)

  def home
    @user = Struct.new(:name).new("David")
    @items = [ Item.new("Tea", 3), Item.new("Coffee", 4), Item.new("Cake", 5) ]
  end

  def about; end

  def plain
    render layout: "plain"
  end

  def guide; end

  def frames; end

  def lazy_frame; end

  def signup; end

  def create_signup
    @error = "Name can't be blank" if params[:name].blank?
    render :signup, status: :unprocessable_entity
  end
end
