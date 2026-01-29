$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)
require 'schmooze'

require 'minitest/autorun'

# For minitest 6.x, stub is provided by minitest-mock gem
begin
  require 'minitest/mock'
rescue LoadError
  # minitest 5.x includes mock/stub by default
end
