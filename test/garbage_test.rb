require 'test_helper'

class GarbageTest < Minitest::Test
  class GarbageSchmoozer < Schmooze::Base
    method :test, 'function(){ return 1; }'

    # Expose the finalizer for testing
    def self.create_finalizer(owner_pid, stdin, stdout, stderr, process_thread)
      finalize(owner_pid, stdin, stdout, stderr, process_thread)
    end
  end

  def test_process_is_not_started_until_used
    garbage = GarbageSchmoozer.new(__dir__)
    assert_nil garbage.pid
    garbage.test
    assert garbage.pid
  end

  def test_process_is_closed
    # Create an instance and get its internal state
    garbage = GarbageSchmoozer.new(__dir__)
    garbage.test
    pid = garbage.pid

    # Get the internal process data
    stdin = garbage.instance_variable_get(:@_schmooze_stdin)
    stdout = garbage.instance_variable_get(:@_schmooze_stdout)
    stderr = garbage.instance_variable_get(:@_schmooze_stderr)
    process_thread = garbage.instance_variable_get(:@_schmooze_process_thread)

    # Create and call the finalizer manually
    finalizer = GarbageSchmoozer.create_finalizer(Process.pid, stdin, stdout, stderr, process_thread)
    finalizer.call

    # Verify the process was killed
    assert_raises Errno::ESRCH do
      Process.kill(0, pid)
    end
  end
end
