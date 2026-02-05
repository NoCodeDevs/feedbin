#!/usr/bin/env ruby
require 'nokogiri'
require 'feedjira'
require 'open-uri'
require 'pg'

conn = PG.connect(host: 'localhost', port: 5433, dbname: 'feedbin_development', user: 'art4')

puts "="*60
puts "IMPORTING MAJOR PUBLICATIONS"
puts "="*60

# Clear existing data
puts "\nClearing old data..."
conn.exec('DELETE FROM entries')
conn.exec('DELETE FROM feeds')

# Parse OPML
opml = Nokogiri::XML(File.read('major_feeds.opml'))
feeds_data = opml.xpath('//outline[@xmlUrl]').map do |outline|
  { title: outline['title'], url: outline['xmlUrl'], site_url: outline['htmlUrl'] }
end

puts "Found #{feeds_data.length} feeds to import\n\n"

total_entries = 0
total_with_images = 0
failed_feeds = []

feeds_data.each_with_index do |feed_data, i|
  begin
    print "[#{i+1}/#{feeds_data.length}] #{feed_data[:title]}... "
    
    # Fetch with timeout and user agent
    content = URI.open(
      feed_data[:url], 
      'User-Agent' => 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
      read_timeout: 12,
      open_timeout: 8
    ).read
    
    parsed = Feedjira.parse(content) rescue nil
    
    unless parsed && parsed.entries && parsed.entries.any?
      puts "no entries"
      next
    end
    
    # Create feed record
    result = conn.exec_params(
      "INSERT INTO feeds (title, feed_url, site_url, created_at, updated_at) VALUES ($1, $2, $3, NOW(), NOW()) RETURNING id",
      [feed_data[:title], feed_data[:url], feed_data[:site_url]]
    )
    feed_id = result[0]['id']
    
    # Process entries - get up to 20 per feed
    entries_added = 0
    entries_with_images = 0
    
    parsed.entries.first(20).each do |item|
      # Get content
      content_html = item.content || item.summary || ''
      summary_html = item.summary || item.content || ''
      
      # Extract image from multiple sources
      image_url = nil
      
      # 1. Check media:content or media:thumbnail
      if item.respond_to?(:media_content) && item.media_content
        image_url = item.media_content
      elsif item.respond_to?(:media_thumbnail) && item.media_thumbnail
        image_url = item.media_thumbnail
      elsif item.respond_to?(:image) && item.image
        image_url = item.image
      end
      
      # 2. Check enclosure
      if image_url.nil? && item.respond_to?(:enclosure_url) && item.enclosure_url
        enc = item.enclosure_url.to_s
        image_url = enc if enc.match?(/\.(jpg|jpeg|png|gif|webp)/i) || enc.include?('image')
      end
      
      # 3. Extract from content HTML
      if image_url.nil?
        doc = Nokogiri::HTML(content_html + summary_html)
        img = doc.at('img[src]')
        if img
          src = img['src'].to_s
          image_url = src unless src.start_with?('data:') || src.length < 10
        end
      end
      
      # 4. Check for og:image style attributes in raw XML
      if image_url.nil? && content_html.include?('src=')
        match = content_html.match(/src=["']([^"']+\.(jpg|jpeg|png|gif|webp)[^"']*)/i)
        image_url = match[1] if match
      end
      
      title = (item.title || 'Untitled').to_s.gsub(/<[^>]+>/, '').strip[0..500]
      url = item.url.to_s
      summary = summary_html.to_s[0..5000]
      published = item.published || Time.now
      public_id = SecureRandom.hex(10)
      
      conn.exec_params(
        "INSERT INTO entries (feed_id, title, url, summary, content, published, public_id, image_url, created_at, updated_at) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, NOW(), NOW())",
        [feed_id, title, url, summary, content_html[0..10000], published, public_id, image_url]
      )
      
      entries_added += 1
      entries_with_images += 1 if image_url
    end
    
    total_entries += entries_added
    total_with_images += entries_with_images
    
    puts "#{entries_added} entries (#{entries_with_images} with images)"
    
  rescue => e
    puts "ERROR: #{e.message[0..50]}"
    failed_feeds << feed_data[:title]
  end
  
  sleep 0.3 # Rate limiting
end

puts "\n" + "="*60
puts "IMPORT COMPLETE"
puts "="*60
puts "Total feeds: #{conn.exec("SELECT COUNT(*) FROM feeds")[0]['count']}"
puts "Total entries: #{total_entries}"
puts "Entries with images: #{total_with_images}"
puts "Failed feeds: #{failed_feeds.length}"
if failed_feeds.any?
  puts "\nFailed feeds:"
  failed_feeds.each { |f| puts "  - #{f}" }
end

conn.close
