# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_09_29_180000) do
  create_table "search_cache_entries", force: :cascade do |t|
    t.datetime "expires_at", null: false
    t.string "fingerprint", null: false
    t.text "payload", null: false
    t.index ["fingerprint"], name: "index_search_cache_entries_on_fingerprint", unique: true
  end

  create_table "search_leases", force: :cascade do |t|
    t.datetime "expires_at"
    t.string "owner_token"
  end

  create_table "search_usage_reservations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_digest"
    t.string "kind", null: false
    t.string "owner_token", null: false
    t.integer "reserved_cents", default: 0, null: false
    t.string "session_digest"
    t.integer "units", null: false
    t.index ["ip_digest", "created_at"], name: "index_search_usage_reservations_on_ip_digest_and_created_at"
    t.index ["kind", "created_at"], name: "index_search_usage_reservations_on_kind_and_created_at"
    t.index ["owner_token", "kind"], name: "index_search_usage_reservations_on_owner_token_and_kind", unique: true
    t.index ["session_digest", "created_at"], name: "idx_on_session_digest_created_at_e1f270efb7"
    t.check_constraint "(kind = 'serpapi' AND units = 2 AND reserved_cents = 0) OR (kind = 'vision' AND units = 1 AND reserved_cents = 3)", name: "valid_search_reservation"
  end
end
