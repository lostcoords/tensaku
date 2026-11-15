class SearchController < ApplicationController
  def show
    render json: DocsSearch.json
  end

  # Written to robots.txt; points crawlers at the sitemap.xml Kiln builds.
  def robots
    render plain: "User-agent: *\nAllow: /\n\nSitemap: #{Kiln.config.url}/sitemap.xml\n"
  end
end
