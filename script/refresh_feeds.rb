#!/usr/bin/env ruby
# Periodic feed refresh - fetches new entries without wiping existing data.
# Run via cron: 0 */4 * * * cd /Users/art4/feedbin && bundle exec ruby script/refresh_feeds.rb
#
# Or run manually: bundle exec ruby script/refresh_feeds.rb

require 'nokogiri'
require 'feedjira'
require 'open-uri'
require 'pg'

def db_connect
  if ENV['DATABASE_URL'] && !ENV['DATABASE_URL'].empty?
    PG.connect(ENV['DATABASE_URL'])
  else
    PG.connect(
      host: ENV.fetch('DB_HOST', 'localhost'),
      port: ENV.fetch('DB_PORT', '5433').to_i,
      dbname: ENV.fetch('DB_NAME', 'feedbin_development'),
      user: ENV.fetch('DB_USER', 'art4')
    )
  end
end

OPML_PATH = File.expand_path('../major_feeds.opml', __dir__)

def extract_image(item)
  content_html = item.content || item.summary || ''
  summary_html = item.summary || item.content || ''
  
  if item.respond_to?(:media_content) && item.media_content
    return item.media_content
  elsif item.respond_to?(:media_thumbnail) && item.media_thumbnail
    return item.media_thumbnail
  elsif item.respond_to?(:image) && item.image
    return item.image
  end
  
  if item.respond_to?(:enclosure_url) && item.enclosure_url
    enc = item.enclosure_url.to_s
    return enc if enc.match?(/\.(jpg|jpeg|png|gif|webp)/i) || enc.include?('image')
  end
  
  doc = Nokogiri::HTML(content_html + summary_html)
  img = doc.at('img[src]')
  return img['src'] if img && !img['src'].to_s.start_with?('data:') && img['src'].to_s.length > 10
  
  match = (content_html + summary_html).match(/src=["']([^"']+\.(jpg|jpeg|png|gif|webp)[^"']*)/i)
  match ? match[1] : nil
end

conn = db_connect

# Get existing feeds (by feed_url) and their IDs
existing_feeds = {}
conn.exec("SELECT id, feed_url FROM feeds").each { |row| existing_feeds[row['feed_url']] = row['id'].to_i }

# Get existing entry URLs to avoid duplicates
existing_urls = conn.exec("SELECT url FROM entries").map { |r| r['url'] }.to_set

unless File.exist?(OPML_PATH)
  puts "OPML not found: #{OPML_PATH}"
  exit 1
end

opml = Nokogiri::XML(File.read(OPML_PATH))
feeds_data = opml.xpath('//outline[@xmlUrl]').map do |o|
  { title: o['title'], url: o['xmlUrl'], site_url: o['htmlUrl'] }
end

puts "[#{Time.now}] Refreshing #{feeds_data.length} feeds..."

added = 0
updated_feeds = 0

feeds_data.each do |fd|
  begin
    feed_id = existing_feeds[fd[:url]]
    
    # Create feed if new
    unless feed_id
      result = conn.exec_params(
        "INSERT INTO feeds (title, feed_url, site_url, created_at, updated_at) VALUES ($1, $2, $3, NOW(), NOW()) RETURNING id",
        [fd[:title], fd[:url], fd[:site_url]]
      )
      feed_id = result[0]['id'].to_i
      existing_feeds[fd[:url]] = feed_id
    end

    content = URI.open(
      fd[:url],
      'User-Agent' => 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)',
      read_timeout: 12,
      open_timeout: 8
    ).read

    parsed = Feedjira.parse(content) rescue nil
    next unless parsed&.entries&.any?

    feed_added = 0
    parsed.entries.first(20).each do |item|
      url = item.url.to_s
      next if url.empty? || existing_urls.include?(url)

      content_html = item.content || item.summary || ''
      summary_html = item.summary || item.content || ''
      title = (item.title || 'Untitled').to_s.gsub(/<[^>]+>/, '').strip[0..500]
      summary = summary_html.to_s[0..5000]
      published = item.published || Time.now
      image_url = extract_image(item)
      public_id = SecureRandom.hex(10)

      conn.exec_params(
        "INSERT INTO entries (feed_id, title, url, summary, content, published, public_id, image_url, created_at, updated_at) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, NOW(), NOW())",
        [feed_id, title, url, summary, content_html[0..10000], published, public_id, image_url]
      )
      existing_urls.add(url)
      feed_added += 1
      added += 1
    end

    updated_feeds += 1 if feed_added > 0
  rescue => e
    # Silent fail for cron - log if verbose
    puts "  #{fd[:title]}: #{e.message}" if ENV['VERBOSE']
  end

  sleep 0.2
end

puts "[#{Time.now}] Done: #{added} new entries from #{updated_feeds} feeds"
conn.close
