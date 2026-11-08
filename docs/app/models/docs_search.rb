# The documents behind the search dialog, served as /search.json. MiniSearch indexes them in the
# browser, so search works the same on the dev server and the static site. Each page is one document,
# and so is each of its h2 and h3 sections, with the text up to the next heading.
module DocsSearch
  GROUPS = { "Pages" => "document-text", "Sections" => "hashtag" }.freeze
  SKIPPED = "pre, svg, script, template, .lc-code-block".freeze

  Document = Data.define(:group, :title, :detail, :url, :text, :featured)

  def self.json
    JSON.generate(icons: GROUPS, documents: documents.map(&:to_h)) + "\n"
  end

  def self.documents
    pages = Docs::PAGES.to_h { [ it, article(it) ] }
    pages.map { page_document(*it) } + pages.flat_map { section_documents(*it) }
  end

  # The page's article as the build writes it, without code, icons and scripts.
  def self.article(page)
    Nokogiri::HTML5(Kiln.render(path(page))).at_css("article").tap { it.css(SKIPPED).each(&:remove) }
  end

  def self.path(page) = "/#{page.slug}"

  def self.page_document(page, body)
    detail = body.at_css("p")&.text.to_s.squish
    Document.new(group: "Pages", title: page.title, detail:, url: path(page), text: body.css("p, li").map(&:text).join(" ").squish, featured: page.group == "Start")
  end

  def self.section_documents(page, body)
    sections = []
    body.element_children.each do |node|
      if %w[h2 h3].include?(node.name) && node["id"]
        sections << { title: node.text.squish, url: "#{path(page)}##{node["id"]}", text: +"" }
      elsif sections.any?
        sections.last[:text] << " " << node.text
      end
    end
    sections.map { Document.new(group: "Sections", title: it[:title], detail: page.title, url: it[:url], text: it[:text].squish, featured: false) }
  end
end
