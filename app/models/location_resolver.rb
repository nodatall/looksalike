require "json"

class LocationResolver
  class InvalidZip < StandardError
    def initialize(*)
      super("Enter a five-digit US ZIP code.")
    end
  end

  class UnmappedZip < StandardError
    def initialize(*)
      super("We could not find a supported Craigslist area for that ZIP code.")
    end
  end

  QUERY_VERSION = "craigslist-area-v1".freeze
  DATA_DIRECTORY = File.expand_path("../../data/locations", __dir__).freeze
  CATALOG = JSON.parse(File.read(File.join(DATA_DIRECTORY, "areas.json")), freeze: true)
  POSTAL_CODES = File.foreach(File.join(DATA_DIRECTORY, "postal_codes.tsv")).to_h do |line|
    zip, country, state, place, latitude, longitude = line.chomp.split("\t")
    [ zip, { country: country.freeze, state: state.freeze, place: place.freeze,
      latitude: Float(latitude), longitude: Float(longitude) }.freeze ]
  end.freeze

  Result = Data.define(:zip, :country, :state, :place, :latitude, :longitude,
    :hostname, :area_name, :area_id, :area_latitude, :area_longitude,
    :search_origin, :mapping_version, :query_version, :mapping_rule)

  def initialize(catalog: CATALOG, postal_codes: POSTAL_CODES)
    @postal_codes = postal_codes
    @mapping_version = catalog.fetch("mapping_version")
    @areas = catalog.fetch("areas").to_h { |area| [ area.fetch("hostname"), area ] }.freeze
    @us_areas = @areas.values.select { |area| area.fetch("country") == "US" }.freeze
    @zip_overrides = catalog.fetch("zip_overrides")
    @country_overrides = catalog.fetch("country_overrides")
  end

  def resolve(zip)
    raise InvalidZip, cause: nil unless zip.is_a?(String) && /\A[0-9]{5}\z/.match?(zip)

    postal = @postal_codes[zip]
    raise UnmappedZip, cause: nil unless postal

    area, rule = select_area(zip, postal)
    raise UnmappedZip, cause: nil unless area && area.fetch("country") == postal.fetch(:country)

    Result.new(zip: zip.dup.freeze, **postal,
      hostname: area.fetch("hostname"), area_name: area.fetch("display_name"), area_id: area.fetch("area_id"),
      area_latitude: area.fetch("latitude"), area_longitude: area.fetch("longitude"),
      search_origin: area.fetch("search_origin"), mapping_version: @mapping_version,
      query_version: QUERY_VERSION, mapping_rule: rule)
  end

  private
    def select_area(zip, postal)
      if (host = @zip_overrides[zip])
        [ @areas[host], "zip_override" ]
      elsif (host = @country_overrides[postal.fetch(:country)])
        [ @areas[host], "country_override" ]
      elsif postal.fetch(:country) == "US"
        [ @us_areas.min_by { |area| [ distance(postal, area), area.fetch("hostname") ] }, "nearest_center" ]
      end
    end

    def distance(postal, area)
      lat, lon, other_lat, other_lon = [ postal.fetch(:latitude), postal.fetch(:longitude), area.fetch("latitude"), area.fetch("longitude") ].map { |degrees| degrees * Math::PI / 180 }
      haversine = Math.sin((other_lat - lat) / 2)**2 + Math.cos(lat) * Math.cos(other_lat) * Math.sin((other_lon - lon) / 2)**2
      haversine = haversine.clamp(0, 1)
      6371 * 2 * Math.atan2(Math.sqrt(haversine), Math.sqrt(1 - haversine))
    end

  DEFAULT = new

  def self.resolve(zip)
    DEFAULT.resolve(zip)
  end
end
