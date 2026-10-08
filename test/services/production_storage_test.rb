require "test_helper"
require "tmpdir"
require "active_support/testing/constant_stubbing"

class ProductionStorageTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::ConstantStubbing

  def production_config
    ActiveRecord::DatabaseConfigurations.new(Rails.application.config.database_configuration)
      .configs_for(env_name: "production", name: "primary")
  end

  def with_environment(values)
    previous = values.to_h { |key, _| [ key, ENV[key] ] }
    values.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    yield
  ensure
    previous.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  def replace_method(object, name, replacement)
    original = object.method(name)
    local = object.singleton_class.instance_methods(false).include?(name)
    object.define_singleton_method(name, replacement)
    yield
  ensure
    object.singleton_class.remove_method(name)
    object.define_singleton_method(name, original) if local
  end

  test "missing production volume fails before connection checkout without creating a database" do
    with_environment("DATABASE_URL" => nil, "RAILWAY_VOLUME_MOUNT_PATH" => nil) do
      config = production_config
      assert_equal ProductionStorage::DATABASE_PATH, config.database
      existed = File.exist?(config.database)
      replace_method(Rails, :env, -> { ActiveSupport::StringInquirer.new("production") }) do
        replace_method(ApplicationRecord, :connection_db_config, -> { config }) do
          replace_method(ApplicationRecord, :connection_pool, -> { flunk "Storage guard must precede the connection pool" }) do
            assert_raises(SearchStore::Error) { SearchStore.new.lookup("photo") }
          end
        end
      end
      assert_equal existed, File.exist?(config.database)
    end
  end

  test "resolved Rails production config stays pinned and unexpected URLs fail before mount access" do
    urls = [ "sqlite3:/tmp/production.sqlite3", "sqlite3:storage/production.sqlite3",
      "sqlite3:///app/storage/production.sqlite3", "#{ProductionStorage::DATABASE_URL}?database=/tmp/other.sqlite3",
      "postgresql://localhost/unexpected" ]
    urls.each do |url|
      with_environment("DATABASE_URL" => url) do
        config = production_config
        assert_equal "sqlite3", config.adapter
        assert_equal ProductionStorage::DATABASE_PATH, config.database
        replace_method(ProductionStorage, :validate_mount!, ->(**) { flunk "Reject DATABASE_URL before touching storage" }) do
          assert_raises(ProductionStorage::Unavailable) { ProductionStorage.validate!(config: config) }
        end
      end
    end
    with_environment("DATABASE_URL" => ProductionStorage::DATABASE_URL) do
      checked_mount = false
      replace_method(ProductionStorage, :validate_mount!, ->(**) { checked_mount = true; raise ProductionStorage::Unavailable }) do
        assert_raises(ProductionStorage::Unavailable) { ProductionStorage.validate!(config: production_config) }
      end
      assert checked_mount, "The canonical URL must reach the actual mount check"
    end
  end

  test "writable directory and claimed volume env cannot impersonate an actual mount" do
    Dir.mktmpdir("unmounted-search-storage-") do |directory|
      directory = File.realpath(directory)
      assert File.writable?(directory)
      stub_const(ProductionStorage, :MOUNT_PATH, directory) do
        assert_raises(ProductionStorage::Unavailable) do
          ProductionStorage.validate_mount!(env: { "RAILWAY_VOLUME_MOUNT_PATH" => directory })
        end
      end
      assert_empty Dir.children(directory)
    end
  end
end
