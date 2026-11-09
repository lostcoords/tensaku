module Docs
  Page = Data.define(:slug, :title, :group)

  # The sidebar, in order. Each page is app/views/pages/<slug>.html.md.
  PAGES = [
    Page.new("introduction", "Introduction", "Start"),
    Page.new("installation", "Installation", "Start"),
    Page.new("editing", "Editing text", "Use"),
    Page.new("notes", "Notes", "Use"),
    Page.new("architecture", "Architecture", "Reference"),
    Page.new("producers", "Attributes and producers", "Reference"),
    Page.new("configuration", "Configuration", "Reference"),
    Page.new("safety", "Safety and limits", "Reference")
  ].freeze

  def self.page(slug) = PAGES.find { it.slug == slug }

  # Headings for "On this page": [level, id, text] for each h2 and h3.
  def self.outline(html)
    Nokogiri::HTML5.fragment(html).css("h2[id], h3[id]").map { [ it.name[1].to_i, it["id"], it.text.squish ] }
  end
end
