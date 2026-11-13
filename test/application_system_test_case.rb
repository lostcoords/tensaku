require "test_helper"
require "capybara/playwright"

# The same stack as our other apps: Capybara on Playwright, Chromium by default. SYSTEM_TEST_BROWSER=webkit
# runs the suite in WebKit (Safari's engine), and SYSTEM_TEST_HEADED=1 shows the browser.
class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  SYSTEM_TEST_BROWSERS = %w[chromium webkit].freeze

  def self.system_test_browser
    ENV.fetch("SYSTEM_TEST_BROWSER", "chromium").tap do |name|
      raise ArgumentError, "SYSTEM_TEST_BROWSER must be one of #{SYSTEM_TEST_BROWSERS.join(", ")}" unless SYSTEM_TEST_BROWSERS.include?(name)
    end
  end

  # Rails reserves :playwright for its own driver, so ours goes by another name.
  Capybara.register_driver :playwright_browser do |app|
    Capybara::Playwright::Driver.new(app,
      browser_type: system_test_browser.to_sym,
      headless: !ENV["SYSTEM_TEST_HEADED"],
      viewport: { width: 1400, height: 900 },
      locale: "en-US",
      timeout: 15)
  end

  driven_by :playwright_browser

  # Browser tests write to the dummy app's real files, so every writable file is restored afterwards.
  WATCHED = %w[app/views app/components config/locales content].freeze

  setup do
    Capybara.server = :puma, { Silent: true }
    @snapshot = WATCHED.flat_map { Dir[Rails.root.join(it, "**/*").to_s] }.select { File.file?(it) }.to_h { [ it, File.binread(it) ] }
  end

  teardown do
    @snapshot.each { |path, content| File.binwrite(path, content) unless File.exist?(path) && File.binread(path) == content }
    ActionView::LookupContext::DetailsKey.clear
    I18n.reload!
  end

  def overlay
    find("tensaku-overlay", visible: :all).shadow_root
  end

  def wait_for_overlay
    assert page.evaluate_script("window.__tensaku === true"), "overlay didn't boot"
  end

  # Waits for a condition outside the page, such as a file the server writes.
  def assert_eventually(timeout: 5)
    deadline = Time.now + timeout
    sleep 0.1 until yield || Time.now > deadline
    assert yield
  end

  def view(path)
    Rails.root.join(path).read
  end

  # Waits for the tools to finish unrolling, since a tool is clipped until they do.
  def open_toolbar
    overlay.find(".corner").click
    overlay.find(".dock.settled")
  end

  # Alt-click opens the menu; E picks its edit action.
  def alt_edit(element)
    element.click(:alt)
    overlay.find(".menu")
    press("e")
  end

  KEYS = { up: "ArrowUp", down: "ArrowDown", left: "ArrowLeft", right: "ArrowRight", enter: "Enter", escape: "Escape",
           ctrl: "Control", control: "Control", meta: "Meta", alt: "Alt", shift: "Shift" }.freeze

  # Presses keys on whatever has focus: press(:up), press(:ctrl, "c") for a chord.
  def press(*keys)
    chord = keys.flatten.map { KEYS.fetch(it.to_s.downcase.to_sym, it.to_s) }.join("+")
    playwright { it.keyboard.press(chord) }
  end

  def playwright(&block)
    page.driver.with_playwright_page(&block)
  end

  def mouse
    playwright(&:mouse)
  end

  # The centre of a Capybara element, in viewport coordinates.
  def center_of(element)
    page.evaluate_script("(() => { const r = arguments[0].getBoundingClientRect(); return [r.x + r.width / 2, r.y + r.height / 2] })()", element)
  end

  # Drags with the mouse, holding modifier (such as "Alt") when given.
  def drag(from, to, modifier: nil)
    playwright do |pw|
      pw.keyboard.down(modifier) if modifier
      pw.mouse.move(*from)
      pw.mouse.down
      pw.mouse.move(*to, steps: 5)
      pw.mouse.up
      pw.keyboard.up(modifier) if modifier
    end
  end

  # Replaces the text of an editable field in the editor with real key presses: select all, then type.
  def type_in_editor(text, field: 0)
    overlay.all(".editor .editable")[field].click
    playwright do |pw|
      pw.keyboard.press("ControlOrMeta+a")
      pw.keyboard.insert_text(text)
    end
  end
end
