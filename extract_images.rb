#!/usr/bin/env ruby
require 'nokogiri'
require 'pg'

conn = PG.connect(host: 'localhost', port: 5433, dbname: 'feedbin_development', user: 'art4')

# Get all entries
entries = conn.exec("SELECT id, summary, content FROM entries")
puts "Processing #{entries.count} entries..."

updated = 0
entries.each do |entry|
  html = entry['content'] || entry['summary'] || ''
  next if html.empty?
  
  doc = Nokogiri::HTML(html)
  
  # Find first image
  img = doc.at('img[src]')
  next unless img
  
  src = img['src']
  next if src.nil? || src.empty? || src.start_with?('data:')
  
  # Update entry with image_url
  conn.exec_params("UPDATE entries SET image_url = $1 WHERE id = $2", [src, entry['id']])
  updated += 1
end

puts "Updated #{updated} entries with images"
conn.close
