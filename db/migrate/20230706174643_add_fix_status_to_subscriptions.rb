class AddFixStatusToSubscriptions < ActiveRecord::Migration[7.0]
  def change
    add_column :subscriptions, :fix_status, :bigint
    change_column_default(:subscriptions, :fix_status, from: nil, to: 0)
    # Backfill job skipped in migrations (requires Redis; on fresh DB no rows to backfill)
  end
end
