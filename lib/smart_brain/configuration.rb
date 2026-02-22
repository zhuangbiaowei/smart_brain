# frozen_string_literal: true

require 'yaml'

module SmartBrain
  class Configuration
    DEFAULT_PATH = File.expand_path('../../config/brain.yml', __dir__)

    def self.load(path = nil)
      file_path = path || DEFAULT_PATH
      data = File.exist?(file_path) ? YAML.safe_load(File.read(file_path), symbolize_names: true) : {}
      new(data || {})
    end

    attr_reader :raw

    def initialize(raw)
      @raw = raw
    end

    def policies
      raw.fetch(:policies, {})
    end

    def retention
      policies.fetch(:retention, {})
    end

    def retrieval
      policies.fetch(:retrieval, {})
    end

    def composition
      policies.fetch(:composition, {})
    end

    def observability
      policies.fetch(:observability, {})
    end
  end
end
