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
    result = Timeout.timeout(remaining, Exceeded) { yield }
    remaining
    result
  end
end
