require "tempfile"

# The paid-search ledger must never fall back to the container's filesystem.
module ProductionStorage
  MOUNT_PATH = "/app/storage".freeze
  DATABASE_PATH = "#{MOUNT_PATH}/production.sqlite3".freeze
  DATABASE_URL = "sqlite3:#{DATABASE_PATH}".freeze
  class Unavailable < StandardError; end

  def self.validate_mount!(env: ENV)
    raise Unavailable unless env["RAILWAY_VOLUME_MOUNT_PATH"] == MOUNT_PATH
    raise Unavailable unless File.directory?(MOUNT_PATH) && File.realpath(MOUNT_PATH) == MOUNT_PATH
    # An ordinary writable directory is not proof of a mounted Railway volume.
    mounted = File.foreach("/proc/self/mountinfo").any? do |line|
      line.split[4] == MOUNT_PATH
    end
    raise Unavailable unless mounted
    true
  rescue SystemCallError, IOError
    raise Unavailable, cause: nil
  end

  def self.validate!(config:, env: ENV)
    url = env["DATABASE_URL"]
    raise Unavailable unless url.nil? || url.empty? || url == DATABASE_URL
    raise Unavailable unless config.adapter == "sqlite3" && config.database == DATABASE_PATH
    validate_mount!(env: env)
    raise Unavailable unless File.writable?(MOUNT_PATH)
    # SQLite and its WAL/SHM sidecars must not resolve outside the mount.
    [ DATABASE_PATH, "#{DATABASE_PATH}-wal", "#{DATABASE_PATH}-shm", "#{DATABASE_PATH}-journal" ].each do |path|
      raise Unavailable if File.symlink?(path)
      raise Unavailable if File.exist?(path) && (!File.file?(path) || !File.writable?(path))
    end
    # Test real write access after dropping privileges; never create a database.
    Tempfile.create(".storage-check-", MOUNT_PATH) { |file| file.write("ok") }
    true
  rescue SystemCallError, IOError
    raise Unavailable, cause: nil
  end
end
