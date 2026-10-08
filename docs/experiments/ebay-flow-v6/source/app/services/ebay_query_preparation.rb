# Prepares a query only. The caller owns Lens/eBay traffic and durable accounting.
class EbayQueryPreparation
  Result = Data.define(:status, :query, :category, :source, :metadata)

  def initialize(vision_client: Vision::Client.new, clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
    @vision_client = vision_client
    @clock = clock
  end

  def call(lens_response:, photo:, deadline:, before_vision_dispatch:)
    lens = SearchQuery.call(lens_response)
    fallback_reason = PhotoQuery.fallback_reason(lens)
    metadata = { lens_version: lens.version, trigger_version: PhotoQuery::TRIGGER_VERSION, phrase_version: PhotoQuery::VERSION,
      lens_category: lens.category, fallback_reason: fallback_reason }
    deadline.remaining
    unless fallback_reason
      return Result.new(status: "ready", query: lens.phrase, category: lens.category, source: "lens", metadata: metadata.merge(category: lens.category))
    end
    started = @clock.call
    available = deadline.remaining - 10
    return Result.new(status: "insufficient_time", query: nil, category: nil, source: "vision", metadata: metadata) unless available.positive?
    vision_deadline = SearchDeadline.new(seconds: [ 15, available ].min, clock: @clock)
    metadata = metadata.merge(Vision::Client.metadata)
    response = deadline.within do
      @vision_client.recognize(photo: photo, deadline: vision_deadline, before_dispatch: before_vision_dispatch)
    end
    vision_deadline.remaining
    answer = PhotoQuery.call(response.answer)
    metadata = metadata.merge(usage: response.usage, duration_ms: ((@clock.call - started) * 1000).round)
    if answer.status == "recognized"
      metadata = metadata.merge(category: answer.category, traits: answer.traits)
      Result.new(status: "ready", query: answer.phrase, category: answer.category, source: "vision", metadata: metadata)
    else
      Result.new(status: answer.status, query: nil, category: nil, source: "vision", metadata: metadata)
    end
  rescue Vision::Client::Error, PhotoValidator::Invalid, SearchDeadline::Exceeded => error
    status = error.is_a?(SearchDeadline::Exceeded) ? "timeout" : error.code.to_s
    metadata = (metadata || {}).merge(duration_ms: started ? ((@clock.call - started) * 1000).round : 0)
    Result.new(status: status, query: nil, category: nil, source: "vision", metadata: metadata)
  end
end
