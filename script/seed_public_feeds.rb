#!/usr/bin/env ruby
# Seed feeds so the public homepage has articles. Run on Heroku:
#   heroku run 'rails runner load "script/seed_public_feeds.rb"' -a YOUR_APP
#
# This creates feeds (and initial entries) from a few RSS URLs, marks them for
# the crawler, clears the 15-min throttle, and enqueues FeedCrawler::Schedule.

FEED_URLS = [
  "https://www.theverge.com/rss/index.xml",
  "https://feeds.arstechnica.com/arstechnica/index",
  "https://daringfireball.net/feeds/json",
].freeze

puts "Feeds: #{Feed.count}, Entries: #{Entry.count}"

FEED_URLS.each do |url|
  next if Feed.exists?(feed_url: url)
  begin
    response = Feedkit::Request.download(url)
    parsed = response.parse
    next if parsed.blank? || parsed.entries.blank?
    feed = Feed.create_from_parsed_feed(parsed, entry_limit: 30)
    feed.update_column(:standalone_request_at, Time.current)
    puts "  Added: #{feed.title} (#{feed.entries.count} entries)"
  rescue => e
    puts "  Skip #{url}: #{e.message[0..80]}"
  end
end

# So the next Schedule run actually does refresh_feeds (instead of "last crawl too recent")
Sidekiq.redis { _1.del(FeedCrawler::Schedule::LAST_REFRESH_KEY) }
FeedCrawler::Schedule.perform_async
puts "Enqueued FeedCrawler::Schedule. Feeds: #{Feed.count}, Entries: #{Entry.count}"
