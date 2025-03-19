require_relative "lib/openapi_resolver/version"

Gem::Specification.new do |spec|
  spec.name = "openapi_resolver"
  spec.version = OpenapiResolver::VERSION
  spec.authors = ["Ohkubo Kohei"]
  spec.email = ["kuboon@trick-with.net"]

  spec.summary = "Extracts json schema from OpenApi document"
  spec.homepage = "https://github.com/kuboon/openapi-resolver.rb"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2"

  spec.metadata = {
    "bug_tracker_uri" => "https://github.com/kuboon/openapi-resolver.rb/issues",
    "changelog_uri" => "https://github.com/kuboon/openapi-resolver.rb/releases",
    "source_code_uri" => "https://github.com/kuboon/openapi-resolver.rb",
    "homepage_uri" => spec.homepage,
    "rubygems_mfa_required" => "true"
  }

  # Specify which files should be added to the gem when it is released.
  spec.files = Dir.glob(%w[LICENSE.txt README.md {exe,lib}/**/*]).reject { |f| File.directory?(f) }
  # spec.bindir = "exe"
  # spec.executables = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]
end
