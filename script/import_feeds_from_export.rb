#!/usr/bin/env ruby
# Import feeds from data/feed_urls.txt (created by script/export_feeds.rb on dev).
# Run on Heroku after deploying the repo that contains data/feed_urls.txt.
#
# Usage (preferred - avoids shell quoting issues):
#   heroku run rails feeds:import_from_export -a YOUR_APP
#
# Optional: FEED_URLS_FILE=/path/to/file (default: data/feed_urls.txt)
#           ENTRY_LIMIT=50 (default: 50 entries per feed on first fetch)

path = ENV.fetch("FEED_URLS_FILE", Rails.root.join("data", "feed_urls.txt").to_s)
path = Rails.root.join(path) unless Pathname.new(path).absolute?
unless File.file?(path)
  puts "File not found: #{path}. Export from dev first: RAILS_ENV=development rails runner script/export_feeds.rb"
  exit 1
end

urls = File.readlines(path).map(&:strip).reject(&:blank?).uniq
entry_limit = (ENV["ENTRY_LIMIT"] || 50).to_i

puts "Feeds: #{Feed.count}, Entries: #{Entry.count}"
puts "Importing #{urls.size} URLs from #{path} (entry_limit=#{entry_limit})..."

added = 0
skipped = 0
errors = 0

urls.each do |url|
  if Feed.exists?(feed_url: url)
    skipped += 1
    next
  end
  begin
    response = Feedkit::Request.download(url)
    parsed = response.parse
    if parsed.blank? || parsed.entries.blank?
      puts "  Skip (no entries): #{url[0..60]}..."
      errors += 1
      next
    end
    feed = Feed.create_from_parsed_feed(parsed, entry_limit: entry_limit)
    feed.update_column(:standalone_request_at, Time.current)
    added += 1
    puts "  [#{added}/#{urls.size}] #{feed.title} (#{feed.entries.count} entries)"
  rescue => e
    puts "  Error #{url[0..50]}...: #{e.message[0..80]}"
    errors += 1
  end
end

puts "\nDone. Added: #{added}, already present: #{skipped}, errors: #{errors}"
puts "Feeds: #{Feed.count}, Entries: #{Entry.count}"

if added > 0
  Sidekiq.redis { _1.del(FeedCrawler::Schedule::LAST_REFRESH_KEY) }
  FeedCrawler::Schedule.perform_async
  puts "Enqueued FeedCrawler::Schedule for ongoing refreshes."
end
