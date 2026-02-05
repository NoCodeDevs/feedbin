namespace :feeds do
  desc "Refresh all feeds from OPML (adds new entries only)"
  task :refresh do
    # Run standalone script (no Rails env) to avoid IO timeouts from iCloud/sync
    root = File.expand_path("../..", __dir__)
    script = File.join(root, "script/refresh_feeds.rb")
    sh "cd #{root} && bundle exec ruby #{script}"
  end
end
