module Docs
  Page = Data.define(:slug, :title, :group)

  # The sidebar, in order. Each page is app/views/pages/<slug>.html.md, except the changelog.
  PAGES = [
    Page.new("introduction", "Introduction", "Start"),
    Page.new("installation", "Installation", "Start"),
    Page.new("editing", "Editing text", "Use"),
    Page.new("notes", "Notes", "Use"),
    Page.new("architecture", "Architecture", "Reference"),
    Page.new("producers", "Attributes and producers", "Reference"),
    Page.new("configuration", "Configuration", "Reference"),
    Page.new("safety", "Safety and limits", "Reference"),
    Page.new("changelog", "Changelog", "Reference")
  ].freeze

  # The changelog page renders the gem's CHANGELOG.md, so it is written once.
  CHANGELOG = Rails.root.join("../CHANGELOG.md").expand_path

  def self.changelog = Kiln::Content.file(CHANGELOG)

  # The newest released version, from the first "## 0.1.0 (2026-11-08)" heading of the changelog.
  def self.release = CHANGELOG.read[/^## (\d+\.\d+\.\d+\S*) \(/, 1]

  def self.page(slug) = PAGES.find { it.slug == slug }

  # Headings for "On this page": [level, id, text] for each h2 and h3.
  def self.outline(html)
    Nokogiri::HTML5.fragment(html).css("h2[id], h3[id]").map { [ it.name[1].to_i, it["id"], it.text.squish ] }
  end
end
