require "vips"
require "tempfile"

class PhotoValidator
  MAX_BYTES = 450_000
  MAX_PIXELS = 20_000_000
  PNG_SIGNATURE = "\x89PNG\r\n\x1A\n".b.freeze

  class Invalid < StandardError
    MESSAGES = {
      too_large: "Choose a smaller photo and try again.",
      unsupported: "Choose a JPEG, PNG, or WebP photo.",
      dimensions: "Choose a photo no larger than 20 megapixels.",
      animated: "Choose a still photo instead of an animation.",
      malformed: "This photo could not be read. Choose another photo."
    }.freeze
    attr_reader :code

    def initialize(code)
      @code = code
      super(MESSAGES.fetch(code))
    end
  end

  Photo = Data.define(:bytes, :content_type, :width, :height) do
    def inspect
      "#<PhotoValidator::Photo #{width}x#{height} #{content_type}>"
    end
    alias_method :to_s, :inspect
  end

  # Consumes and deletes an uploaded Tempfile even when validation fails.
  # Strings and caller-owned non-temporary IO stay in memory; no new temp is created.
  def self.call(upload, deadline:)
    input = upload.respond_to?(:tempfile) ? upload.tempfile : upload
    deadline.within do
      bytes = if input.is_a?(String)
        input.b
      else
        input.rewind
        input.read(MAX_BYTES + 1).to_s.b
      end
      raise Invalid.new(:too_large) if bytes.bytesize > MAX_BYTES
      format = format_for(bytes)
      reject_animation!(bytes, format)
      image = Vips::Image.public_send("#{format}load_buffer", bytes, access: :sequential, fail_on: :warning)
      width, height = image.width, image.height
      raise Invalid.new(:dimensions) unless width.positive? && height.positive? && width * height <= MAX_PIXELS
      raise Invalid.new(:animated) if image.get_typeof("n-pages").positive? && image.get("n-pages") > 1
      deadline.remaining
      image.avg # Force every pixel to decode after bounded header validation.
      deadline.remaining
      Photo.new(bytes: bytes.freeze, content_type: "image/#{format == :jpeg ? 'jpeg' : format}", width: width, height: height)
    end
  rescue Vips::Error, IOError, SystemCallError
    raise Invalid.new(:malformed), cause: nil
  ensure
    input.close! if input.is_a?(Tempfile)
  end

  def self.format_for(bytes)
    return :jpeg if bytes.start_with?("\xFF\xD8\xFF".b)
    return :png if bytes.start_with?(PNG_SIGNATURE)
    return :webp if bytes.start_with?("RIFF") && bytes.byteslice(8, 4) == "WEBP"
    raise Invalid.new(:unsupported)
  end
  private_class_method :format_for

  def self.reject_animation!(bytes, format)
    return if format == :jpeg
    offset = format == :png ? 8 : 12
    while offset + 8 <= bytes.bytesize
      if format == :png
        size = bytes.byteslice(offset, 4).unpack1("N")
        kind = bytes.byteslice(offset + 4, 4)
        raise Invalid.new(:animated) if kind == "acTL"
        offset += size + 12
      else
        kind = bytes.byteslice(offset, 4)
        size = bytes.byteslice(offset + 4, 4).unpack1("V")
        animated_flag = kind == "VP8X" && bytes.getbyte(offset + 8).to_i & 2 != 0
        raise Invalid.new(:animated) if animated_flag || %w[ANIM ANMF].include?(kind)
        offset += size + 8 + size % 2
      end
      raise Invalid.new(:malformed) if offset > bytes.bytesize
    end
  end
  private_class_method :reject_animation!
end
