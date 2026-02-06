namespace :feeds do
  desc "Seed database with curated RSS feeds across categories"
  task seed: :environment do
    FEEDS = {
      # AI/ML
      "AI/ML" => [
        "https://openai.com/blog/rss.xml",
        "https://blogs.nvidia.com/feed/",
        "https://machinelearningmastery.com/feed/",
        "https://www.deepmind.com/blog/rss.xml",
        "https://ai.googleblog.com/feeds/posts/default",
        "https://www.marktechpost.com/feed/",
        "https://syncedreview.com/feed/",
        "https://www.unite.ai/feed/",
      ],
      # Programming
      "Programming" => [
        "https://dev.to/feed",
        "https://blog.codinghorror.com/rss/",
        "https://martinfowler.com/feed.atom",
        "https://overreacted.io/rss.xml",
        "https://css-tricks.com/feed/",
        "https://www.joelonsoftware.com/feed/",
        "https://blog.cleancoder.com/atom.xml",
        "https://kentcdodds.com/blog/rss.xml",
      ],
      # Tech News
      "Tech" => [
        "https://feeds.arstechnica.com/arstechnica/technology-lab",
        "https://www.theverge.com/rss/index.xml",
        "https://techcrunch.com/feed/",
        "https://www.wired.com/feed/rss",
        "https://feeds.feedburner.com/TechCrunch/",
        "https://www.engadget.com/rss.xml",
        "https://gizmodo.com/rss",
        "https://mashable.com/feeds/rss/all",
      ],
      # Security
      "Security" => [
        "https://krebsonsecurity.com/feed/",
        "https://www.schneier.com/feed/atom/",
        "https://www.bleepingcomputer.com/feed/",
        "https://threatpost.com/feed/",
        "https://www.darkreading.com/rss.xml",
        "https://feeds.feedburner.com/TheHackersNews",
      ],
      # Science
      "Science" => [
        "https://www.quantamagazine.org/feed/",
        "https://www.sciencedaily.com/rss/all.xml",
        "https://www.newscientist.com/feed/home/",
        "https://phys.org/rss-feed/",
        "https://www.nature.com/nature.rss",
        "https://www.sciencemag.org/rss/news_current.xml",
      ],
      # Business
      "Business" => [
        "https://hbr.org/feed",
        "https://feeds.bloomberg.com/technology/news.rss",
        "https://www.entrepreneur.com/latest.rss",
        "https://a16z.com/feed/",
        "https://www.fastcompany.com/latest/rss",
        "https://fortune.com/feed/",
      ],
      # Design
      "Design" => [
        "https://www.smashingmagazine.com/feed/",
        "https://alistapart.com/main/feed/",
        "https://www.designernews.co/stories.rss",
        "https://uxdesign.cc/feed",
        "https://www.creativebloq.com/feed",
        "https://webdesignernews.com/feed/",
      ],
      # Culture
      "Culture" => [
        "https://www.newyorker.com/feed/culture",
        "https://www.theatlantic.com/feed/channel/entertainment/",
        "https://pitchfork.com/feed/feed-news/rss",
        "https://variety.com/feed/",
        "https://www.rollingstone.com/feed/",
        "https://consequenceofsound.net/feed/",
      ],
      # Gaming
      "Gaming" => [
        "https://kotaku.com/rss",
        "https://www.ign.com/articles.rss",
        "https://www.gamespot.com/feeds/mashup/",
        "https://www.polygon.com/rss/index.xml",
        "https://www.rockpapershotgun.com/feed",
        "https://www.eurogamer.net/feed",
      ],
      # News
      "News" => [
        "https://rss.nytimes.com/services/xml/rss/nyt/Technology.xml",
        "https://www.theguardian.com/technology/rss",
        "https://feeds.bbci.co.uk/news/technology/rss.xml",
        "https://www.reuters.com/technology/rss",
      ],
      # Photography
      "Photography" => [
        "https://petapixel.com/feed/",
        "https://fstoppers.com/rss.xml",
        "https://www.dpreview.com/feeds/news.xml",
        "https://www.slrlounge.com/feed/",
      ],
    }

    added = 0
    skipped = 0
    failed = 0

    FEEDS.each do |category, urls|
      puts "\n=== #{category} ==="
      urls.each do |url|
        begin
          # Check if already exists
          existing = Feed.xml.find_by(feed_url: url)
          if existing
            puts "  SKIP: #{url} (already exists)"
            skipped += 1
            next
          end

          # Download and parse
          response = Feedkit::Request.download(url)
          parsed = response.parse
          final_url = response.url

          if parsed.blank? || parsed.entries.blank?
            puts "  FAIL: #{url} (no entries)"
            failed += 1
            next
          end

          # Check again with final URL
          existing = Feed.xml.find_by(feed_url: final_url)
          if existing
            puts "  SKIP: #{url} -> #{final_url} (already exists)"
            skipped += 1
            next
          end

          feed = Feed.create_from_parsed_feed(parsed, entry_limit: 20)
          puts "  OK: #{feed.title} (#{feed.entries.count} entries)"
          added += 1

        rescue => e
          puts "  FAIL: #{url} (#{e.class}: #{e.message.truncate(50)})"
          failed += 1
        end
      end
    end

    puts "\n=== Summary ==="
    puts "Added: #{added}"
    puts "Skipped: #{skipped}"
    puts "Failed: #{failed}"
  end
end
