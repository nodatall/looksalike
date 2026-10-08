class SearchSettings
  LIMITS = {
    daily: [ "SEARCH_DAILY_ATTEMPT_LIMIT", 10 ], rolling: [ "SEARCH_ROLLING_30_DAY_ATTEMPT_LIMIT", 180 ],
    vision_daily: [ "VISION_DAILY_ATTEMPT_LIMIT", 5 ],
    vision_rolling: [ "VISION_ROLLING_30_DAY_ATTEMPT_LIMIT", 90 ]
  }.freeze
  attr_reader :limits, :deadline_seconds

  class Invalid < StandardError; end

  def initialize(env: ENV)
    @limits = LIMITS.to_h do |key, (name, ceiling)|
      value = Integer(env.fetch(name, ceiling.to_s), 10)
      raise Invalid unless value.between?(1, ceiling)
      [ key, value ]
    end
    @deadline_seconds = Float(env.fetch("SEARCH_DEADLINE_SECONDS", "55"))
    raise Invalid unless @deadline_seconds.finite? && @deadline_seconds.positive? && @deadline_seconds <= 55
    flag = env.fetch("LIVE_SEARCH_ENABLED", "false")
    raise Invalid unless %w[true false].include?(flag)
    @enabled = flag == "true" && %w[SERPAPI_API_KEY VENICE_API_KEY].all? { |key| !env[key].to_s.strip.empty? }
  rescue ArgumentError, TypeError
    raise Invalid, cause: nil
  end

  def enabled?
    @enabled
  end
end
