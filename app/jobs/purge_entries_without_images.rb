class PurgeEntriesWithoutImages
  include Sidekiq::Worker
  sidekiq_options queue: :default, retry: false

  def perform
    # Find entries without a processed image (image column is null or missing required keys)
    # Only purge entries older than 1 hour to give image crawler time to process
    scope = Entry.where("created_at < ?", 1.hour.ago)
                 .where(<<~SQL)
                   image IS NULL
                   OR image->>'original_url' IS NULL
                   OR image->>'processed_url' IS NULL
                   OR image->>'width' IS NULL
                   OR image->>'height' IS NULL
                 SQL

    ids = scope.pluck(:id)
    return if ids.empty?

    Sidekiq.logger.info "PurgeEntriesWithoutImages: found #{ids.size} entries to purge"

    ids.each_slice(500) do |batch_ids|
      UnreadEntry.where(entry_id: batch_ids).delete_all
      StarredEntry.where(entry_id: batch_ids).delete_all
      UpdatedEntry.where(entry_id: batch_ids).delete_all rescue nil
      RecentlyReadEntry.where(entry_id: batch_ids).delete_all
      RecentlyPlayedEntry.where(entry_id: batch_ids).delete_all rescue nil
      QueuedEntry.where(entry_id: batch_ids).delete_all rescue nil
      Entry.where(id: batch_ids).delete_all
    end

    Sidekiq.logger.info "PurgeEntriesWithoutImages: purged #{ids.size} entries"
  end
end
