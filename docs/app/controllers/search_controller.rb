class SearchController < ApplicationController
  def show
    render json: DocsSearch.json
  end
end
