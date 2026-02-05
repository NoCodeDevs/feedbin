namespace :feeds do
  desc "Import feeds from data/feed_urls.txt (from dev export). Run: heroku run rails feeds:import_from_export -a APP"
  task import_from_export: :environment do
    load Rails.root.join("script", "import_feeds_from_export.rb").to_s
  end

  # Copy feeds+entries from dev to prod via direct DB copy. No HTTP. Run locally.
  # PRODUCTION_DATABASE_URL=postgres://... rails feeds:copy_to_production
  desc "Copy feeds and entries from dev to prod (no fetch, no IP blocking)"
  task copy_to_production: :environment do
    load Rails.root.join("script", "copy_feeds_to_production.rb").to_s
  end

  desc "Refresh all feeds from OPML (adds new entries only)"
  task :refresh do
    # Run standalone script (no Rails env) to avoid IO timeouts from iCloud/sync
    root = File.expand_path("../..", __dir__)
    script = File.join(root, "script/refresh_feeds.rb")
    sh "cd #{root} && bundle exec ruby #{script}"
  end
end
