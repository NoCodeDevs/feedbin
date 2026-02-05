#!/usr/bin/env ruby
# Import feeds from data/feed_urls.txt (created by script/export_feeds.rb on dev).
#
# Usage:
#   heroku run rails feeds:import_from_export -a YOUR_APP
#
# If feeds fail with "result is not a feed" (sites blocking Heroku IPs), run
# locally against production so requests use your home IP:
#   heroku config -a YOUR_APP  # copy DATABASE_URL and REDIS_URL
#   DATABASE_URL="..." REDIS_URL="..." bundle exec rails runner script/import_feeds_from_export.rb
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

def try_fetch_feed(url)
  response = Feedkit::Request.download(url)
  parsed = response.parse
  parsed if parsed.present? && parsed.entries.present?
end

urls.each do |url|
  if Feed.exists?(feed_url: url)
    skipped += 1
    next
  end
  parsed = nil
  last_error = nil
  urls_to_try = [url]
  urls_to_try.unshift(url.sub(/\Ahttp:\/\//, "https://")) if url.start_with?("http://")
  urls_to_try.uniq!

  urls_to_try.each do |try_url|
    begin
      parsed = try_fetch_feed(try_url)
      break if parsed
    rescue => e
      last_error = e
    end
  end

  if parsed
    begin
      feed = Feed.create_from_parsed_feed(parsed, entry_limit: entry_limit)
      feed.update_column(:standalone_request_at, Time.current)
      added += 1
      puts "  [#{added}/#{urls.size}] #{feed.title} (#{feed.entries.count} entries)"
    rescue => e
      puts "  Error #{url[0..50]}...: #{e.message[0..80]}"
      errors += 1
    end
  else
    puts "  Error #{url[0..50]}...: #{last_error&.message&.[](0..80) || 'unknown'}"
    errors += 1
  end
end

puts "\nDone. Added: #{added}, already present: #{skipped}, errors: #{errors}"
puts "Feeds: #{Feed.count}, Entries: #{Entry.count}"

if added > 0
  begin
    Sidekiq.redis { _1.del(FeedCrawler::Schedule::LAST_REFRESH_KEY) }
    FeedCrawler::Schedule.perform_async
    puts "Enqueued FeedCrawler::Schedule for ongoing refreshes."
  rescue => e
    puts "Could not enqueue Schedule (run on Heroku if needed): #{e.message}"
  end
end
