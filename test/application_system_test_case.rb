require "test_helper"
require "capybara/cuprite"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :cuprite, screen_size: [ 1400, 900 ], options: { headless: ENV["HEADLESS"] != "0", process_timeout: 30, timeout: 15 }

  # Browser tests write to the dummy app's real files, so every writable file is restored afterwards.
  WATCHED = %w[app/views app/components config/locales].freeze

  setup do
    Capybara.server = :puma, { Silent: true }
    @snapshot = WATCHED.flat_map { Dir[Rails.root.join(it, "**/*").to_s] }.select { File.file?(it) }.to_h { [ it, File.binread(it) ] }
    FileUtils.rm_rf(Tensaku::Notes.dir)
  end

  teardown do
    @snapshot.each { |path, content| File.binwrite(path, content) unless File.exist?(path) && File.binread(path) == content }
    FileUtils.rm_rf(Tensaku::Notes.dir)
    ActionView::LookupContext::DetailsKey.clear
    I18n.reload!
  end

  def overlay
    find("tensaku-overlay", visible: :all).shadow_root
  end

  def wait_for_overlay
    assert page.evaluate_script("window.__tensaku === true"), "overlay didn't boot"
  end

  def view(path)
    Rails.root.join(path).read
  end

  def alt_click(element)
    element.click(:alt)
  end

  # Replaces the text of the focused editable field in the editor.
  def type_in_editor(text, field: 0)
    editable = overlay.all(".editor .editable")[field]
    editable.click
    page.driver.browser.keyboard.type([ :Meta, "a" ]) rescue nil
    page.execute_script(<<~JS, text, field)
      const field = document.querySelector("tensaku-overlay").shadowRoot.querySelectorAll(".editor .editable")[arguments[1]];
      field.focus();
      const range = document.createRange(); range.selectNodeContents(field);
      const selection = getSelection(); selection.removeAllRanges(); selection.addRange(range);
      document.execCommand("insertText", false, arguments[0]);
    JS
  end
end
