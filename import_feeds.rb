#!/usr/bin/env ruby
require 'nokogiri'
require 'feedjira'
require 'open-uri'
require 'pg'

# Connect to database
conn = PG.connect(
  host: 'localhost',
  port: 5433,
  dbname: 'feedbin_development',
  user: 'art4'
)

# Clear existing data
puts 'Clearing old data...'
conn.exec('DELETE FROM entries')
conn.exec('DELETE FROM feeds')

# Parse OPML
opml = Nokogiri::XML(File.read('feeds.opml'))
feeds_data = opml.xpath('//outline[@xmlUrl]').map do |outline|
  { title: outline['title'], url: outline['xmlUrl'], site_url: outline['htmlUrl'] }
end

puts "Found #{feeds_data.length} feeds in OPML"

# Import feeds and fetch articles
feeds_data.each_with_index do |feed_data, i|
  begin
    puts "[#{i+1}/#{feeds_data.length}] Fetching: #{feed_data[:title]}"
    
    # Fetch and parse RSS first
    content = URI.open(feed_data[:url], 'User-Agent' => 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)', read_timeout: 15, open_timeout: 10).read
    parsed = Feedjira.parse(content) rescue nil
    
    next unless parsed && parsed.entries && parsed.entries.any?
    
    # Insert feed via SQL
    result = conn.exec_params(
      "INSERT INTO feeds (title, feed_url, site_url, created_at, updated_at) VALUES ($1, $2, $3, NOW(), NOW()) RETURNING id",
      [feed_data[:title], feed_data[:url], feed_data[:site_url]]
    )
    feed_id = result[0]['id']
    
    # Insert entries
    items = parsed.entries[0..14] # Get up to 15 items
    items.each do |item|
      title = (item.title || 'Untitled').to_s[0..500]
      url = item.url.to_s
      summary = (item.summary || item.content || '').to_s[0..5000]
      published = item.published || Time.now
      public_id = SecureRandom.hex(10)
      
      conn.exec_params(
        "INSERT INTO entries (feed_id, title, url, summary, published, public_id, created_at, updated_at) VALUES ($1, $2, $3, $4, $5, $6, NOW(), NOW())",
        [feed_id, title, url, summary, published, public_id]
      )
    end
    puts "  -> Added #{items.length} entries"
  rescue => e
    puts "  -> Error: #{e.message[0..80]}"
  end
end

# Count results
feeds_count = conn.exec("SELECT COUNT(*) FROM feeds")[0]['count']
entries_count = conn.exec("SELECT COUNT(*) FROM entries")[0]['count']
puts "\nDone! Feeds: #{feeds_count}, Entries: #{entries_count}"

conn.close
