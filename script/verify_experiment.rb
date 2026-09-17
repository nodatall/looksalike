#!/usr/bin/env ruby
require_relative "../config/environment"
require "digest"
require "json"

root = Rails.root
path = root.join("docs/experiments/feasibility-v1/manifest.json")
expected = File.read(path.sub_ext(".sha256")).split.first
abort "Experiment manifest checksum changed" unless Digest::SHA256.file(path).hexdigest == expected
manifest = JSON.parse(File.read(path))
manifest.fetch("artifacts").each do |relative, recorded|
  file = root.join(relative)
  abort "Frozen artifact changed: #{relative}" unless file.file? && file.size == recorded.fetch("bytes") && Digest::SHA256.file(file).hexdigest == recorded.fetch("sha256")
end
manifest.fetch("cases").each do |entry|
  image = entry.fetch("photo")
  validated = PhotoValidator.call(File.binread(root.join(image.fetch("path"))), deadline: SearchDeadline.new)
  abort "Invalid frozen photo dimensions" unless [ validated.width, validated.height ] == [ image.fetch("width"), image.fetch("height") ]
  current = LocationResolver.resolve(entry.fetch("zip"))
  %w[hostname area_name search_origin mapping_version query_version mapping_rule].each do |field|
    abort "Frozen location changed: #{entry.fetch('id')} #{field}" unless current.public_send(field) == entry.fetch("location").fetch(field)
  end
end
puts "Verified #{manifest.fetch('cases').length} frozen images/locations and #{manifest.fetch('artifacts').length} artifact hashes; experiment remains #{manifest.fetch('status')}."
