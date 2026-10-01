class CreateSearchState < ActiveRecord::Migration[8.1]
  def change
    create_table :search_cache_entries do |t|
      t.string :fingerprint, null: false
      t.text :payload, null: false
      t.datetime :expires_at, null: false
    end
    add_index :search_cache_entries, :fingerprint, unique: true

    create_table :search_usage_reservations do |t|
      t.string :owner_token, null: false
      t.string :kind, null: false
      t.integer :units, null: false
      t.integer :reserved_cents, null: false, default: 0
      t.string :session_digest
      t.string :ip_digest
      t.datetime :created_at, null: false
    end
    add_index :search_usage_reservations, [ :kind, :created_at ]
    add_index :search_usage_reservations, [ :owner_token, :kind ], unique: true
    add_index :search_usage_reservations, [ :session_digest, :created_at ]
    add_index :search_usage_reservations, [ :ip_digest, :created_at ]
    add_check_constraint :search_usage_reservations, "(kind = 'serpapi' AND units = 2 AND reserved_cents = 0) OR (kind = 'vision' AND units = 1 AND reserved_cents = 3)", name: "valid_search_reservation"

    create_table :search_leases do |t|
      t.string :owner_token
      t.datetime :expires_at
    end
    reversible do |direction|
      direction.up { execute "INSERT INTO search_leases (id) VALUES (1)" }
    end
  end
end
