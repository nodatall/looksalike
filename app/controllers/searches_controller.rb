class SearchesController < ApplicationController
  include ActionController::Live

  # Read session/IP on the request thread before Live starts its streaming thread.
  def process(name)
    @visitor_id = session[:search_visitor_id] ||= SecureRandom.uuid
    @visitor_ip = request.remote_ip
    super
  end

  def create
    response.headers["Content-Type"] = "application/x-ndjson; charset=utf-8"
    response.headers["Cache-Control"] = "no-store"
    response.headers["Last-Modified"] = Time.now.utc.httpdate
    response.headers["X-Accel-Buffering"] = "no"
    photo = params[:photo]
    if photo.respond_to?(:tempfile)
      result = EbaySearch.new.call(photo: photo, session_id: @visitor_id, ip: @visitor_ip, progress: method(:write_event))
    else
      result = { "version" => EbaySearch::VERSION, "status" => "invalid_photo", "message" => "Choose a furniture photo.",
        "source" => "live", "listings" => [], "stages" => [], "attempts" => { "uploads" => 0, "serpapi" => 0, "vision" => 0 },
        "original_attempts" => { "uploads" => 0, "serpapi" => 0, "vision" => 0 } }
    end
    write_event("type" => "result", "result" => result) if result
  rescue EbaySearch::Disconnected
    # Stop the request; committed reservations remain counted.
  ensure
    response.stream.close
    photo.tempfile.close! if photo.respond_to?(:tempfile)
  end

  private
    def write_event(event)
      response.stream.write(JSON.generate(event) + "\n")
    rescue ActionController::Live::ClientDisconnected, IOError, Errno::EPIPE
      raise EbaySearch::Disconnected, cause: nil
    end
end
