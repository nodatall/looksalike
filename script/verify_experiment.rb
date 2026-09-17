#!/usr/bin/env ruby
require_relative "../config/environment"
manifest = ExperimentManifest.new.verify!
puts "Verified #{manifest.data.fetch('cases').length} frozen images/locations and #{manifest.data.fetch('artifacts').length} artifact hashes; experiment remains #{manifest.data.fetch('status')}."
