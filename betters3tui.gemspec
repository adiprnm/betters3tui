# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name = "betters3tui"
  spec.version = "0.2.4"
  spec.authors = ["Adi Purnama"]
  spec.email = ["adi@adipurnm.com"]

  spec.summary = "A TUI (Terminal User Interface) S3-compatible browser"
  spec.description = "Browse S3-compatible storage from your terminal with an interactive interface. Supports multiple S3-compatible services, file search, sorting, and downloading."
  spec.homepage = "https://github.com/adiprnm/betters3tui"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 2.7.0"

  spec.files = Dir.glob("{bin,lib}/**/*") + %w[LICENSE README.md CHANGELOG.md]
  spec.executables = ["betters3tui"]
  spec.require_paths = ["lib"]

  spec.add_dependency "aws-sdk-s3", "~> 1.0"
end
