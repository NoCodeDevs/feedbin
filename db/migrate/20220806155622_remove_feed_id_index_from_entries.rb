class RemoveFeedIdIndexFromEntries < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!

  def up
    remove_index :entries, name: "index_entries_on_feed_id", algorithm: :concurrently if index_exists?(:entries, nil, name: "index_entries_on_feed_id")
  end

  def down
    add_index :entries, :feed_id, algorithm: :concurrently, name: "index_entries_on_feed_id" unless index_exists?(:entries, :feed_id, name: "index_entries_on_feed_id")
  end
end
