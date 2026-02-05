#!/usr/bin/env ruby
# Copy feeds and entries from dev DB directly into production. No HTTP - no IP blocking.
# Run locally (connects to both DBs). No Heroku, no proxy, no fetch.
#
# 1. Get prod DB URL: heroku config:get DATABASE_URL -a calm-journey-58657
# 2. Run: PRODUCTION_DATABASE_URL="postgres://..." rails feeds:copy_to_production
#
# Requires both dev (default) and prod DB to be reachable from your machine.

PROD_DB_URL = ENV["PRODUCTION_DATABASE_URL"]
abort "Set PRODUCTION_DATABASE_URL (from: heroku config:get DATABASE_URL -a YOUR_APP)" if PROD_DB_URL.blank?

# Separate connection for production
class ProdDB < ActiveRecord::Base
  self.abstract_class = true
  establish_connection(PROD_DB_URL)
end

class ProdFeed < ProdDB
  self.table_name = "feeds"
  has_many :entries, class_name: "ProdEntry", foreign_key: :feed_id
end

class ProdEntry < ProdDB
  self.table_name = "entries"
  belongs_to :feed, class_name: "ProdFeed", foreign_key: :feed_id
end

# Columns to copy (skip id, timestamps we'll set)
FEED_COLS = %w[title feed_url site_url subscriptions_count protected push_expiration last_published_entry host self_url feed_type active options hubs settings standalone_request_at last_change_check crawl_data redirected_to].freeze
ENTRY_COLS = %w[title url author summary content published updated entry_id public_id data original source image_url processed_image_url image settings provider provider_id provider_parent_id].freeze

feed_map = {} # dev_id => prod_feed
created_feeds = 0
created_entries = 0

puts "Copying from dev (#{Feed.count} feeds, #{Entry.count} entries) to production..."

Feed.find_each do |dev_feed|
  prod_feed = ProdFeed.find_by(feed_url: dev_feed.feed_url)
  if prod_feed
    feed_map[dev_feed.id] = prod_feed
    next
  end

  attrs = FEED_COLS.to_h { |c| [c, dev_feed[c]] }
  attrs["standalone_request_at"] ||= Time.current # so crawler picks it up
  prod_feed = ProdFeed.create!(attrs)
  feed_map[dev_feed.id] = prod_feed
  created_feeds += 1
  print "."
end

# Map feed_url -> prod feed (stable; feed IDs can differ between dev/prod)
feed_url_to_prod = {}
Feed.find_each { |f| feed_url_to_prod[f.feed_url] = feed_map[f.id] if feed_map[f.id] }

puts "\nCreated #{created_feeds} feeds. Copying entries..."

batch = []
skipped_no_prod = 0
skipped_exists = 0
Entry.includes(:feed).find_each do |dev_entry|
  prod_feed = feed_url_to_prod[dev_entry.feed&.feed_url]
  unless prod_feed
    skipped_no_prod += 1
    next
  end

  pid = dev_entry.public_id.presence || dev_entry.url.presence || dev_entry.entry_id.presence || "e#{dev_entry.id}"
  if ProdEntry.exists?(feed_id: prod_feed.id, public_id: pid)
    skipped_exists += 1
    next
  end

  row = ENTRY_COLS.to_h { |c| [c, dev_entry[c]] }
  row["public_id"] = pid
  row["feed_id"] = prod_feed.id
  row["created_at"] = dev_entry.created_at
  row["updated_at"] = dev_entry.updated_at
  batch << row
  if batch.size >= 100
    ProdEntry.insert_all(batch)
    created_entries += batch.size
    batch.clear
    print "."
  end
rescue => e
  puts "\nError on entry #{dev_entry.id}: #{e.class} #{e.message}"
  raise
end
if batch.any?
  ProdEntry.insert_all(batch)
  created_entries += batch.size
end

puts "\n(skipped: #{skipped_no_prod} no prod feed, #{skipped_exists} already exist)" if skipped_no_prod + skipped_exists > 0

puts "\nDone. Created #{created_feeds} feeds, #{created_entries} entries in production."
puts "Prod now has #{ProdFeed.count} feeds, #{ProdEntry.count} entries."

# Enqueue crawler on prod (requires Redis - we can't easily do this from local)
puts "\nTo trigger feed refresh on Heroku, run:"
puts '  heroku run "rails runner \"Sidekiq.redis { _1.del(FeedCrawler::Schedule::LAST_REFRESH_KEY) }; FeedCrawler::Schedule.perform_async\"" -a calm-journey-58657'
