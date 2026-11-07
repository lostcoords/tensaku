require "application_system_test_case"

# The spike from PLAN decision 5: after a save, how the page catches up on different setups.
class PageUpdateTest < ApplicationSystemTestCase
  def edit(selector, text)
    alt_click find(selector)
    type_in_editor text
    overlay.find(".editor .editable", match: :first).send_keys(:enter)
  end

  test "Hotwire page: morph keeps Stimulus controllers connected and doesn't fire a Turbo visit" do
    visit "/"
    wait_for_overlay
    assert_equal 1, page.evaluate_script("window.helloConnects")
    page.execute_script("window.__visits = 0; document.addEventListener('turbo:visit', () => window.__visits++)")

    # Changed on disk too, so only the refetch and morph can bring this in.
    path = Rails.root.join("app/views/pages/home.html.erb")
    edit "p.intro", "Morphed text."
    assert_selector "p.intro", text: "Morphed text."
    path.write(path.read.sub("<%= render GreetingComponent", %(<p class="extra">Added on disk</p>\n<%= render GreetingComponent)))
    edit "p.intro", "Morphed again."

    assert_selector "p.extra", text: "Added on disk"
    assert_equal 1, page.evaluate_script("window.helloConnects")
    assert_nil page.evaluate_script("window.helloDisconnects")
    assert_equal 0, page.evaluate_script("window.__visits")
  end

  test "Turbo Frames: frame content morphs and lazy frames load again" do
    visit "/frames"
    wait_for_overlay
    assert_selector "p.lazy-text", text: "Loaded lazily."

    edit "p.framed", "Inside a morphed frame."

    assert_selector "p.framed", text: "Inside a morphed frame."
    assert_selector "p.lazy-text", text: "Loaded lazily."
    assert_includes view("app/views/pages/frames.html.erb"), %(<p class="framed">Inside a morphed frame.</p>)
  end

  test "a page without Turbo updates the same way" do
    visit "/plain"
    wait_for_overlay

    edit "p.plain-text", "Still no Turbo."

    assert_selector "p.plain-text", text: "Still no Turbo."
    assert_includes view("app/views/pages/plain.html.erb"), %(<p class="plain-text">Still no Turbo.</p>)
  end

  test "a page reached by a POST updates in place and asks for a reload" do
    visit "/signup"
    click_on "Create account"
    assert_selector "p.error"
    wait_for_overlay

    edit "label", "Full name"

    assert_selector "label", text: "Full name"
    assert overlay.has_css?(".toast", text: "reload to check")
    assert_selector "p.error"
  end
end
