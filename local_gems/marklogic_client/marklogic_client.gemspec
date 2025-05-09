# frozen_string_literal: true

require_relative "lib/marklogic_client/version"

Gem::Specification.new do |spec|
  spec.name = "marklogic_client"
  spec.version = MarklogicClient::VERSION
  spec.authors = ["Manus AI Agent"]
  spec.email = ["agent@example.com"]

  spec.summary = "A Ruby client for MarkLogic NoSQL Database."
  spec.description = "Provides an ActiveRecord-like interface for interacting with MarkLogic, including persistent connections."
  spec.homepage = "https://github.com/example/marklogic_client"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0.0"

  # spec.metadata["allowed_push_host"] = "https://your_gem_server.com" # Optional: Set if you have a private gem server

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/example/marklogic_client"
  spec.metadata["changelog_uri"] = "https://github.com/example/marklogic_client/blob/main/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .github appveyor Gemfile]) # Added .github to exclude
    end
  end
  spec.bindir = "bin"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "activesupport", ">= 7.0", "< 9.0"
  spec.add_dependency "activemodel", ">= 7.0", "< 9.0"
  spec.add_dependency "net-http-persistent", "~> 4.0"

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end

