# Schema-based setup skips migration seed SQL. Preserve any existing lease owner.
SearchLease.find_or_create_by!(id: 1)
