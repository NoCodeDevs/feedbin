class RemoveFeedIdAndEntryIdIndexFromEntries < ActiveRecord::Migration[4.2]
  def up
    # Index may already be gone (e.g. dropped with entry_id column in RemoveEntryIdFromEntries)
    return unless index_exists?(:entries, nil, name: "index_entries_on_feed_id_and_entry_id")

    remove_index(:entries, name: :index_entries_on_feed_id_and_entry_id)
  end

  def down
  end
end
