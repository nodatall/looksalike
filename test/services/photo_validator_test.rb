require "test_helper"
require "zlib"

class PhotoValidatorTest < ActiveSupport::TestCase
  def photo(format = ".jpg", width: 24, height: 16)
    Vips::Image.black(width, height, bands: 3).write_to_buffer(format)
  end

  test "accepts and decodes each allowed format using its bytes" do
    { ".jpg" => "image/jpeg", ".png" => "image/png", ".webp" => "image/webp" }.each do |format, mime|
      result = PhotoValidator.call(photo(format), deadline: SearchDeadline.new)
      assert_equal [ 24, 16, mime ], [ result.width, result.height, result.content_type ]
    end
  end

  test "checks bytes instead of the source MIME or filename and removes upload tempfile" do
    input = Tempfile.new("photo")
    path = input.path
    input.binmode.write(photo(".png"))
    upload = Struct.new(:tempfile, :content_type, :original_filename).new(input, "image/jpeg", "pretend.svg")
    result = PhotoValidator.call(upload, deadline: SearchDeadline.new)
    assert_equal "image/png", result.content_type
    refute File.exist?(path)
    refute_includes result.inspect, result.bytes
    refute_includes result.to_s, result.bytes
  end

  test "rejects oversized bytes, unsupported magic, and truncated decode" do
    cases = [ [ "x" * 450_001, :too_large ], [ "<svg></svg>", :unsupported ], [ photo.byteslice(0, 100), :malformed ] ]
    cases.each do |bytes, code|
      error = assert_raises(PhotoValidator::Invalid) { PhotoValidator.call(bytes, deadline: SearchDeadline.new) }
      assert_equal code, error.code
    end
  end

  test "rejects pixel count from metadata before raster decoding" do
    error = assert_raises(PhotoValidator::Invalid) do
      PhotoValidator.call(photo(".png", width: 5000, height: 4001), deadline: SearchDeadline.new)
    end
    assert_equal :dimensions, error.code
  end

  test "rejects PNG and WebP animation containers" do
    png = photo(".png")
    payload = "acTL" + [ 2, 0 ].pack("NN")
    chunk = [ 8 ].pack("N") + payload + [ Zlib.crc32(payload) ].pack("N")
    png = png.byteslice(0, 33) + chunk + png.byteslice(33..)
    webp = "RIFF" + [ 22 ].pack("V") + "WEBPVP8X" + [ 10 ].pack("V") + "\x02" + "\x00" * 9
    [ png, webp ].each do |bytes|
      error = assert_raises(PhotoValidator::Invalid) { PhotoValidator.call(bytes, deadline: SearchDeadline.new) }
      assert_equal :animated, error.code
    end
  end

  test "Rails filters uploaded content and provider references" do
    fields = %w[photo image image_id api_key]
    params = fields.to_h { |field| [ field, "private-sentinel" ] }
    filtered = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters).filter(params)
    assert_equal fields.to_h { |field| [ field, "[FILTERED]" ] }, filtered
  end

  test "removes failed upload tempfile and checks deadline after validation" do
    input = Tempfile.new("photo")
    path = input.path
    input.write("invalid")
    assert_raises(PhotoValidator::Invalid) { PhotoValidator.call(input, deadline: SearchDeadline.new) }
    refute File.exist?(path)
    assert_raises(SearchDeadline::Exceeded) { PhotoValidator.call(photo, deadline: SearchDeadline.new(seconds: 0)) }
    ticks = [ 0, 0, 0, 56 ]
    deadline = SearchDeadline.new(clock: -> { ticks.shift || 56 })
    assert_raises(SearchDeadline::Exceeded) { PhotoValidator.call(photo, deadline: deadline) }
  end
end
