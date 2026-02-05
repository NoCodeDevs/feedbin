class AddRecentlyPlayedCounterToEntries < ActiveRecord::Migration[5.0]
  disable_ddl_transaction!

  def up
    unless column_exists?(:entries, :recently_played_entries_count)
      add_column :entries, :recently_played_entries_count, :integer
    end
    unless index_exists?(:entries, :recently_played_entries_count, name: "index_entries_on_recently_played_entries_count")
      add_index :entries, :recently_played_entries_count, algorithm: :concurrently, name: "index_entries_on_recently_played_entries_count"
    end
    change_column_default :entries, :recently_played_entries_count, 0

    # Backfill job skipped in migrations (requires Redis; on fresh DB no rows to backfill)
  end

  def down
    remove_column :entries, :recently_played_entries_count
  end
end
