abort "Tests require RAILS_ENV=test" if ENV["RAILS_ENV"] && ENV["RAILS_ENV"] != "test"
ENV["RAILS_ENV"] = "test"
ENV["DATABASE_URL"] = "sqlite3:#{File.expand_path("../storage/test.sqlite3", __dir__)}"
ENV["SERPAPI_API_KEY"] = ""
ENV["OPENAI_API_KEY"] = ""
ENV["LIVE_SEARCH_ENABLED"] = "false"
require_relative "../config/environment"
expected_database = Rails.root.join("storage/test.sqlite3").to_s
abort "Unsafe test database configuration" unless ActiveRecord::Base.connection_db_config.adapter == "sqlite3" && ActiveRecord::Base.connection_db_config.database == expected_database
require "rails/test_help"
require "webmock/minitest"

WebMock.disable_net_connect!

module ActiveSupport
  class TestCase
    # This small suite has no ActiveRecord schema yet. Ledger races use their own connections.
    parallelize(workers: 1)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
  end
end
