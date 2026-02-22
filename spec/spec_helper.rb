# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'smart_brain'

RSpec.configure do |config|
  config.order = :random
  Kernel.srand config.seed
end
