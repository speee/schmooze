require 'test_helper'

class LocalScriptTest < Minitest::Test
  class LocalScriptSchmoozer < Schmooze::Base
    dependencies localapp: './localapp'

    method :test, 'localapp.test'
  end

  def setup
    @schmoozer = LocalScriptSchmoozer.new(File.join(__dir__, 'fixtures', 'local_script'))
  end

  def teardown
    if @schmoozer&.pid
      @schmoozer.close rescue nil
    end
  end

  def test_usage
    assert_equal 456, @schmoozer.test
  end
end
