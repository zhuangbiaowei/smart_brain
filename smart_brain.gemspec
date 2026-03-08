lib = File.expand_path("lib", __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "smart_brain/version"

Gem::Specification.new do |spec|
  spec.name = "smart_brain"
  spec.version = SmartBrain::VERSION
  spec.authors = ["SmartBrain Team"]
  spec.email = ["team@smartbrain.dev"]

  spec.summary = "Agent memory runtime and context composer"
  spec.description = "SmartBrain provides commit_turn and compose_context APIs for agent memory, retrieval planning, evidence fusion, and context assembly."
  spec.homepage = "https://github.com/smart-ai/smart_brain"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 2.7.0"

  spec.metadata["source_code_uri"] = spec.homepage

  spec.files = Dir.glob(
    %w[
      LICENSE
      README*
      config/brain.yml
      db/**/*.sql
      example.rb
      conversation_demo.rb
      agents/**/*.rb
      workers/**/*.rb
      templates/**/*.erb
      lib/**/*.rb
    ]
  ).select { |file| File.file?(file) }.sort

  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |file| File.basename(file) }
  spec.require_paths = ["lib"]

  spec.add_dependency "dry-struct", "~> 1.7"
  spec.add_dependency "dry-validation", "~> 1.11"
  spec.add_dependency "faraday", "~> 2.11"
  spec.add_dependency "oj", "~> 3.16"
  spec.add_dependency "pg", "~> 1.5"
  spec.add_dependency "sequel", "~> 5.87"
  spec.add_dependency "smart_rag", "~> 0.1"

  spec.add_development_dependency "bundler", ">= 2.0"
  spec.add_development_dependency "debug", "~> 1.11"
  spec.add_development_dependency "pgvector", "~> 0.3.2"
  spec.add_development_dependency "puma", "~> 7.2"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rdbg", "~> 0.1.0"
  spec.add_development_dependency "rspec", "~> 3.13"
  spec.add_development_dependency "sinatra", "~> 4.2"
  spec.add_development_dependency "smart_agent", "~> 0.2.3"
end
