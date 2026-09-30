require "timeout"

class SearchDeadline
  class Exceeded < StandardError
    def initialize(*)
      super("The search took too long. Please try again.")
    end
  end

  def initialize(seconds: 55, clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
    @clock = clock
    @expires_at = @clock.call + seconds
  end

  def remaining
    seconds = @expires_at - @clock.call
    raise Exceeded, cause: nil unless seconds.positive?
    seconds
  end

  def within
    remaining
    owners = Thread.current.thread_variable_get(:looksalike_deadline_timers)
    unless owners
      owners = {}
      Thread.current.thread_variable_set(:looksalike_deadline_timers, owners)
    end
    if owners.key?(self)
      result = yield
      remaining
      return result
    end

    # Nested clients/transports share this timer; duplicate interrupts can break cleanup.
    owners[self] = true
    begin
      result = Timeout.timeout(remaining, Exceeded) { yield }
      remaining
      result
    ensure
      owners.delete(self)
    end
  end
end
