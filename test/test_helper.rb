$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)
require 'schmooze'

require 'minitest/autorun'

# For minitest 6.x compatibility, try to require minitest/mock
# This provides stub functionality
begin
  require 'minitest/mock'
rescue LoadError
  # minitest/mock not available, stub might still work in older versions
end
