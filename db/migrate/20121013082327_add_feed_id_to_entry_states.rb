class AddFeedIdToEntryStates < ActiveRecord::Migration[4.2]
  def up
    add_column :entry_states, :feed_id, :integer
    add_index :entry_states, :feed_id

    # Backfill feed_id from entries (avoid referencing removed EntryState model)
    execute <<-SQL
      UPDATE entry_states
      SET feed_id = entries.feed_id
      FROM entries
      WHERE entry_states.entry_id = entries.id
    SQL
  end

  def down
    remove_column :entry_states, :feed_id
  end
end
