class RemoveFeedIdAndEntryIdIndexFromEntries < ActiveRecord::Migration[4.2]
  def up
    remove_index(:entries, name: :index_entries_on_feed_id_and_entry_id, if_exists: true)
  end

  def down
  end
end
