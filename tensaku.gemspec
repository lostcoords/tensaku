require_relative "lib/tensaku/version"

Gem::Specification.new do |spec|
  spec.name        = "tensaku"
  spec.version     = Tensaku::VERSION
  spec.authors     = [ "David Afonso" ]
  spec.email       = [ "dav@davafons.com" ]
  spec.homepage    = "https://tensaku.lostcoords.com"
  spec.summary     = "Fix your Rails app in the browser."
  spec.description = "Tensaku lets you click text on a Rails page in development and write the change back to the " \
    "ERB template, the locale YAML or the Markdown source, or leave notes on elements and areas that a coding " \
    "agent reads with the exact file and line. Built on Herb through ReActionView. Development only."
  spec.license     = "MIT"

  spec.required_ruby_version = ">= 4.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/lostcoords/tensaku"
  spec.metadata["changelog_uri"] = "https://github.com/lostcoords/tensaku/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"
  spec.metadata["allowed_push_host"] = "https://rubygems.org"

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["lib/**/*", "exe/*", "app/assets/tensaku.js", "skills/**/*", "LICENSE", "README.md", "CHANGELOG.md"]
  end
  spec.bindir = "exe"
  spec.executables = [ "tensaku" ]

  # Herb and ReActionView are before 1.0 and Tensaku loads one of Herb's internal files, so each new
  # minor version needs a check before it's allowed. Rails 8.2 needs a look too (see PLAN.md).
  spec.add_dependency "railties", ">= 8.1", "< 8.2"
  spec.add_dependency "actionpack", ">= 8.1", "< 8.2"
  spec.add_dependency "herb", "~> 0.11.2"
  spec.add_dependency "reactionview", "~> 0.6.1"
  spec.add_dependency "sqlite3", ">= 2.0"
end
