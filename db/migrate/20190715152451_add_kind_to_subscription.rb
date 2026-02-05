class AddKindToSubscription < ActiveRecord::Migration[5.1]
  disable_ddl_transaction!

  def up
    add_column :subscriptions, :kind, :bigint
    change_column_default(:subscriptions, :kind, 0)
    add_index :subscriptions, :kind, algorithm: :concurrently
    # Backfill job skipped in migrations (requires Redis; on fresh DB no rows to backfill)
  end

  def down
    remove_column :subscriptions, :kind
  end
end
