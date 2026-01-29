require 'test_helper'
require 'timeout'

class FinalizeTest < Minitest::Test
  # Use a long-running Node.js process that doesn't exit when stdin is closed
  # This is critical for testing the finalizer because the issue only manifests
  # when the process keeps running after stdin is closed.
  class LongRunningSchmoozer < Schmooze::Base
    # This method keeps the Node.js process running with a setTimeout
    # Even after stdin is closed, the process will wait for the timeout
    method :echo, 'function(x) { setTimeout(() => {}, 60000); return x; }'
  end

  def setup
    @pids_to_cleanup = []
  end

  def teardown
    # Clean up any remaining processes to avoid resource exhaustion
    @pids_to_cleanup.each do |pid|
      begin
        Process.kill(:KILL, pid)
        Process.wait(pid)
      rescue Errno::ESRCH, Errno::ECHILD
        # Process already dead or not our child
      end
    end
  end

  # Test that the finalizer does not hang when the process is still running.
  #
  # This test reproduces an issue where the old finalizer implementation
  # used `Process.kill(0, pid)` which only checks if the process exists
  # instead of actually terminating it. This caused `process_thread.value`
  # to block indefinitely because the Node.js process was waiting for stdin.
  #
  # The fix uses `Process.kill(:KILL, pid)` to actually terminate the process
  # before waiting for it.
  def test_finalizer_does_not_hang
    $stderr.puts "[DEBUG] test_finalizer_does_not_hang: start" if ENV['SCHMOOZE_DEBUG']
    finalizer = nil
    pid = nil

    # Capture the finalizer without letting it run automatically
    ObjectSpace.stub :define_finalizer, proc { |_s, p| finalizer = p } do
      schmoozer = LongRunningSchmoozer.new(__dir__)
      schmoozer.echo("test")
      pid = schmoozer.pid
      @pids_to_cleanup << pid

      # Verify the process is running
      assert pid, "Process should be running"
      Process.kill(0, pid)  # Should not raise if process is running
      $stderr.puts "[DEBUG] test_finalizer_does_not_hang: created pid=#{pid}" if ENV['SCHMOOZE_DEBUG']
    end

    # Run the finalizer with a timeout to detect hanging
    $stderr.puts "[DEBUG] test_finalizer_does_not_hang: calling finalizer..." if ENV['SCHMOOZE_DEBUG']
    assert_raises_nothing_within(5) do
      finalizer.call
    end
    $stderr.puts "[DEBUG] test_finalizer_does_not_hang: finalizer completed" if ENV['SCHMOOZE_DEBUG']

    # Verify the process was killed
    assert_raises Errno::ESRCH do
      Process.kill(0, pid)
    end
    @pids_to_cleanup.delete(pid)  # Already cleaned up by finalizer
    $stderr.puts "[DEBUG] test_finalizer_does_not_hang: done" if ENV['SCHMOOZE_DEBUG']
  end

  # Test that finalizer properly cleans up multiple instances
  # This tests the scenario where GC.stress is enabled and many instances
  # are created and garbage collected.
  def test_finalizer_handles_multiple_instances_under_gc_pressure
    pids = []
    finalizers = []

    $stderr.puts "[DEBUG] Creating 5 schmoozer instances..." if ENV['SCHMOOZE_DEBUG']
    ObjectSpace.stub :define_finalizer, proc { |_s, p| finalizers << p } do
      5.times do |i|
        $stderr.puts "[DEBUG] Creating instance #{i+1}..." if ENV['SCHMOOZE_DEBUG']
        $stderr.flush if ENV['SCHMOOZE_DEBUG']
        schmoozer = LongRunningSchmoozer.new(__dir__)
        $stderr.puts "[DEBUG] Instance #{i+1} created, calling echo..." if ENV['SCHMOOZE_DEBUG']
        $stderr.flush if ENV['SCHMOOZE_DEBUG']
        schmoozer.echo("test")
        pids << schmoozer.pid
        @pids_to_cleanup << schmoozer.pid
        $stderr.puts "[DEBUG] Instance #{i+1} ready, pid=#{schmoozer.pid}" if ENV['SCHMOOZE_DEBUG']
        $stderr.flush if ENV['SCHMOOZE_DEBUG']
      end
    end

    assert_equal 5, pids.length
    assert_equal 5, finalizers.length

    $stderr.puts "[DEBUG] Calling finalizers..." if ENV['SCHMOOZE_DEBUG']
    # All finalizers should complete without hanging
    assert_raises_nothing_within(15) do
      finalizers.each_with_index do |finalizer, i|
        $stderr.puts "[DEBUG] Calling finalizer #{i+1} for pid=#{pids[i]}..." if ENV['SCHMOOZE_DEBUG']
        $stderr.flush if ENV['SCHMOOZE_DEBUG']
        finalizer.call
        $stderr.puts "[DEBUG] Finalizer #{i+1} completed" if ENV['SCHMOOZE_DEBUG']
        $stderr.flush if ENV['SCHMOOZE_DEBUG']
      end
    end
    $stderr.puts "[DEBUG] All finalizers completed" if ENV['SCHMOOZE_DEBUG']

    # All processes should be terminated
    pids.each do |pid|
      assert_raises Errno::ESRCH do
        Process.kill(0, pid)
      end
      @pids_to_cleanup.delete(pid)  # Already cleaned up by finalizer
    end
  end

  # Test fork safety: finalizer should only kill process in the original parent
  def test_finalizer_is_fork_safe
    skip "Fork not available on this platform" unless Process.respond_to?(:fork)

    finalizer = nil
    pid = nil

    ObjectSpace.stub :define_finalizer, proc { |_s, p| finalizer = p } do
      schmoozer = LongRunningSchmoozer.new(__dir__)
      schmoozer.echo("test")
      pid = schmoozer.pid
      @pids_to_cleanup << pid
    end

    # Fork and try to run finalizer in child
    child_pid = fork do
      # In child process, finalizer should not kill the process
      # because owner_pid != Process.pid
      finalizer.call
      # Process should still be running (not killed by child)
      begin
        Process.kill(0, pid)
        exit 0  # Success - process still running
      rescue Errno::ESRCH
        exit 1  # Failure - process was killed
      end
    end

    _, status = Process.waitpid2(child_pid)
    assert_equal 0, status.exitstatus, "Child should not kill parent's process"

    # Process should still be running
    Process.kill(0, pid)  # Should not raise if process is still running

    # Now run finalizer in parent - it should kill the process
    assert_raises_nothing_within(5) do
      finalizer.call
    end

    assert_raises Errno::ESRCH do
      Process.kill(0, pid)
    end
    @pids_to_cleanup.delete(pid)  # Already cleaned up by finalizer
  end

  # Test that the close method does not hang with long-running processes.
  # This is similar to the finalizer issue - close() needs to kill the
  # process before waiting for it to exit.
  def test_close_does_not_hang
    schmoozer = LongRunningSchmoozer.new(__dir__)
    schmoozer.echo("test")
    pid = schmoozer.pid
    @pids_to_cleanup << pid

    assert pid, "Process should be running"
    Process.kill(0, pid)  # Should not raise

    # close() should not hang
    assert_raises_nothing_within(5) do
      schmoozer.close
    end

    # Verify the process was killed
    assert_raises Errno::ESRCH do
      Process.kill(0, pid)
    end
    @pids_to_cleanup.delete(pid)  # Already cleaned up by close()
  end

  private

  def assert_raises_nothing_within(seconds, message = nil)
    Timeout.timeout(seconds) do
      yield
    end
  rescue Timeout::Error
    flunk(message || "Block did not complete within #{seconds} seconds (likely hung)")
  end
end
