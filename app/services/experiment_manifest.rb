require "digest"
require "json"

class ExperimentManifest
  class Invalid < StandardError; end
  attr_reader :data, :checksum

  def initialize(root: Rails.root)
    @root = Pathname(root)
  end

  def verify!(deadline: SearchDeadline.new)
    deadline.within do
      path = @root.join("docs/experiments/feasibility-v1/manifest.json")
      @checksum = Digest::SHA256.file(path).hexdigest
      raise Invalid, "Experiment manifest checksum changed" unless @checksum == File.read(path.sub_ext(".sha256")).strip
      @data = JSON.parse(File.read(path))
      data.fetch("artifacts").each do |relative, recorded|
        file = @root.join(relative)
        raise Invalid, "Frozen artifact changed" unless file.file? && file.size == recorded.fetch("bytes") && Digest::SHA256.file(file).hexdigest == recorded.fetch("sha256")
      end
      data.fetch("cases").each do |entry|
        image = entry.fetch("photo")
        validated = PhotoValidator.call(photo(entry), deadline: deadline)
        raise Invalid, "Invalid frozen photo dimensions" unless [ validated.width, validated.height ] == [ image.fetch("width"), image.fetch("height") ]
        current = LocationResolver.resolve(entry.fetch("zip"))
        %w[hostname area_name search_origin mapping_version query_version mapping_rule].each do |field|
          raise Invalid, "Frozen location changed" unless current.public_send(field) == entry.fetch("location").fetch(field)
        end
      end
      self
    end
  rescue KeyError, JSON::ParserError, SystemCallError
    raise Invalid, "Frozen experiment files are unavailable or invalid", cause: nil
  end

  def photo(entry)
    File.binread(@root.join(entry.fetch("photo").fetch("path")))
  end
end
