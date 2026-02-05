namespace :feedbin do
  desc "Purge entries that have no image (image_url NULL or blank) and their dependent records"
  task purge_entries_without_images: :environment do
    scope = Entry.where("image_url IS NULL OR TRIM(COALESCE(image_url, '')) = ''")
    ids = scope.pluck(:id)
    total = ids.size
    puts "Found #{total} entries without images to purge."

    if total.zero?
      puts "Nothing to do."
      next
    end

    # Delete dependent records first, then entries (in batches if large)
    ids.each_slice(1000) do |batch_ids|
      UnreadEntry.where(entry_id: batch_ids).delete_all
      StarredEntry.where(entry_id: batch_ids).delete_all
      UpdatedEntry.where(entry_id: batch_ids).delete_all
      RecentlyReadEntry.where(entry_id: batch_ids).delete_all
      RecentlyPlayedEntry.where(entry_id: batch_ids).delete_all
      QueuedEntry.where(entry_id: batch_ids).delete_all
      # digest_entries has ON DELETE CASCADE from entries
      # Image table may not exist in all environments
      Entry.where(id: batch_ids).delete_all
    end

    puts "Done. Purged #{total} entries without images."
  end
end
