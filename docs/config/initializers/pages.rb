module Docs
  Page = Data.define(:slug, :title, :group)

  # The sidebar, in order. Each page is app/views/pages/<slug>.html.md.
  PAGES = [
    Page.new("introduction", "Introduction", "Start"),
    Page.new("installation", "Installation", "Start"),
    Page.new("editing", "Editing text", "Use"),
    Page.new("notes", "Notes", "Use"),
    Page.new("agents", "Notes for agents", "Use"),
    Page.new("producers", "Attributes and producers", "Reference"),
    Page.new("configuration", "Configuration", "Reference"),
    Page.new("safety", "Safety and limits", "Reference")
  ].freeze

  def self.page(slug) = PAGES.find { it.slug == slug }
end
