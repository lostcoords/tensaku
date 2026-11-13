module KeysHelper
  # Markdown pages write keys as <kbd>alt+shift+t</kbd>, in lc_kbd's notation. They render as lc_kbd,
  # which reads Alt Shift T, and ⌥ ⇧ T on Apple platforms once its controller runs.
  def platform_keys(html)
    String.new(html).gsub(%r{<kbd>([^<]+)</kbd>}) { lc_kbd(CGI.unescapeHTML($1)) }.html_safe
  end
end
