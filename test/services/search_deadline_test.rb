require "test_helper"

class SearchDeadlineTest < ActiveSupport::TestCase
  test "uses one absolute monotonic budget and checks after work" do
    now = 100.0
    deadline = SearchDeadline.new(clock: -> { now })
    now += 30
    assert_equal 25, deadline.remaining
    assert_raises(SearchDeadline::Exceeded) { deadline.within { now += 26 } }
  end

  test "bounds a stalled whole operation independently of streaming socket timeouts" do
    finished = false
    assert_raises(SearchDeadline::Exceeded) do
      SearchDeadline.new(seconds: 0.02).within { sleep 0.2; finished = true }
    end
    refute finished, "The timer must interrupt the block, not only reject its eventual result"
  end
end
