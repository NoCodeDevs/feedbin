# frozen_string_literal: true

class DeduplicateEntriesAndAddUniqueFeedUrl < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!

  def up
    safety_assured do
      # 1. Find duplicate (feed_id, url) groups (url present). Keep entry with min(id) per group.
      duplicate_groups = execute(<<~SQL).to_a
      SELECT feed_id, url, array_agg(id ORDER BY id) AS ids
      FROM entries
      WHERE url IS NOT NULL AND url != ''
      GROUP BY feed_id, url
      HAVING count(*) > 1
    SQL

    duplicate_groups.each do |row|
      ids = row["ids"].to_s.gsub(/[{}]/, "").split(",").map(&:to_i).sort
      kept_id = ids.first
      duplicate_ids = ids[1..]

      next if duplicate_ids.empty?

      duplicate_ids.each do |dup_id|
        # Reassign join tables to the kept entry
        [
          "unread_entries",
          "starred_entries",
          "recently_read_entries",
          "recently_played_entries",
          "queued_entries",
          "updated_entries",
          "digest_entries",
          "unreads"
        ].each do |table|
          next unless table_exists?(table) && column_exists?(table, :entry_id)

          execute <<~SQL.squish
            UPDATE #{table}
            SET entry_id = #{kept_id}
            WHERE entry_id = #{dup_id}
          SQL
        end
        execute "DELETE FROM entries WHERE id = #{dup_id}"
      end

      # Remove duplicate (user_id, entry_id) rows for this kept_id (one pass per group)
      %w[unread_entries starred_entries recently_read_entries recently_played_entries queued_entries updated_entries unreads].each do |table|
        next unless table_exists?(table)

        execute <<~SQL.squish
          DELETE FROM #{table} a
          USING #{table} b
          WHERE a.user_id = b.user_id AND a.entry_id = b.entry_id AND a.id > b.id
        SQL
      end
      if table_exists?("digest_entries")
        execute <<~SQL.squish
          DELETE FROM digest_entries a
          USING digest_entries b
          WHERE a.entry_id = b.entry_id AND a.smart_rule_id = b.smart_rule_id AND a.id > b.id
        SQL
      end
    end

    end

    # 2. Add unique index on (feed_id, md5(url)) for entries with url to prevent future duplicates
    add_index :entries,
              "feed_id, md5(url)",
              unique: true,
              where: "url IS NOT NULL AND url != ''",
              name: "index_entries_on_feed_id_and_url_hash",
              algorithm: :concurrently
  end

  def down
    remove_index :entries, name: "index_entries_on_feed_id_and_url_hash", algorithm: :concurrently, if_exists: true
  end
end
