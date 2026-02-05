#!/usr/bin/env ruby
# Export all feed URLs from the current DB (run with dev) to data/feed_urls.txt.
# Then deploy and run script/import_feeds_from_export.rb on Heroku to add them to production.
#
# Usage (from project root):
#   RAILS_ENV=development rails runner script/export_feeds.rb
#
# Output: data/feed_urls.txt (one URL per line). Commit and push, then on Heroku:
#   heroku run 'rails runner load "script/import_feeds_from_export.rb"' -a YOUR_APP

path = Rails.root.join("data", "feed_urls.txt")
FileUtils.mkdir_p(Rails.root.join("data"))
urls = Feed.pluck(:feed_url).compact.uniq
  .map { |u| u.start_with?("http://") ? u.sub(/\Ahttp:\/\//, "https://") : u }
  .uniq.sort
File.write(path, urls.join("\n") + "\n")
puts "Exported #{urls.size} feed URLs to #{path}"
