require_relative "lib/tensaku/version"

Gem::Specification.new do |spec|
  spec.name        = "tensaku"
  spec.version     = Tensaku::VERSION
  spec.authors     = [ "David Afonso" ]
  spec.email       = [ "dav@davafons.com" ]
  spec.homepage    = "https://tensaku.lostcoords.com"
  spec.summary     = "Edit text and leave notes for your coding agent on a running Rails page, in development."
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
    Dir["lib/**/*", "app/assets/tensaku.js", "skills/**/*", "LICENSE", "README.md", "CHANGELOG.md"]
  end

  spec.add_dependency "railties", ">= 8.1"
  spec.add_dependency "actionpack", ">= 8.1"
  spec.add_dependency "herb", ">= 0.11.2"
  spec.add_dependency "reactionview", ">= 0.6.1"
end
