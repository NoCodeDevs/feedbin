#!/usr/bin/env ruby
require 'pg'

conn = PG.connect(host: 'localhost', port: 5433, dbname: 'feedbin_development', user: 'art4')

# Category mappings based on feed title
CATEGORY_MAP = {
  # Tech
  'The Verge' => 'Tech',
  'Wired' => 'Tech',
  'Ars Technica' => 'Tech',
  'TechCrunch' => 'Tech',
  'Engadget' => 'Tech',
  'MIT Technology Review' => 'Tech',
  'Gizmodo' => 'Tech',
  'CNET' => 'Tech',
  'Mashable' => 'Tech',
  'VentureBeat' => 'Tech',
  
  # News
  'BBC News' => 'News',
  'BBC Technology' => 'News',
  'NPR' => 'News',
  'The Guardian' => 'News',
  'The Guardian Tech' => 'News',
  'Al Jazeera' => 'News',
  'ABC News' => 'News',
  'CBS News' => 'News',
  'NBC News' => 'News',
  'Vox' => 'News',
  'Slate' => 'News',
  'Quartz' => 'News',
  
  # Business
  'Bloomberg' => 'Business',
  'Forbes' => 'Business',
  'Business Insider' => 'Business',
  'Fortune' => 'Business',
  'Inc.' => 'Business',
  'Fast Company' => 'Business',
  'Harvard Business Review' => 'Business',
  'Entrepreneur' => 'Business',
  'CNBC' => 'Business',
  'MarketWatch' => 'Business',
  
  # Science
  'Scientific American' => 'Science',
  'Nature' => 'Science',
  'Science Daily' => 'Science',
  'Space.com' => 'Science',
  'NASA' => 'Science',
  'Phys.org' => 'Science',
  'New Scientist' => 'Science',
  'Live Science' => 'Science',
  'Popular Science' => 'Science',
  'Smithsonian' => 'Science',
  
  # AI/ML
  'OpenAI Blog' => 'AI/ML',
  'Google AI Blog' => 'AI/ML',
  'Meta AI' => 'AI/ML',
  'DeepMind' => 'AI/ML',
  'Towards Data Science' => 'AI/ML',
  'KDnuggets' => 'AI/ML',
  'Machine Learning Mastery' => 'AI/ML',
  'Analytics Vidhya' => 'AI/ML',
  'Data Science Central' => 'AI/ML',
  'The AI Blog' => 'AI/ML',
  
  # Design
  'Dezeen' => 'Design',
  'Core77' => 'Design',
  'Design Milk' => 'Design',
  'Creative Bloq' => 'Design',
  "It's Nice That" => 'Design',
  'Behance' => 'Design',
  'Dribbble' => 'Design',
  'Smashing Magazine' => 'Design',
  'CSS-Tricks' => 'Design',
  'A List Apart' => 'Design',
  
  # Culture
  'The Atlantic' => 'Culture',
  'The New Yorker' => 'Culture',
  'The Conversation' => 'Culture',
  'Longreads' => 'Culture',
  'Aeon' => 'Culture',
  'Nautilus' => 'Culture',
  'Brain Pickings' => 'Culture',
  
  # Gaming
  'IGN' => 'Gaming',
  'Kotaku' => 'Gaming',
  'Polygon' => 'Gaming',
  'GameSpot' => 'Gaming',
  'PC Gamer' => 'Gaming',
  'Rock Paper Shotgun' => 'Gaming',
  'Eurogamer' => 'Gaming',
  'GamesRadar' => 'Gaming',
  'Destructoid' => 'Gaming',
  
  # Programming
  'Hacker Noon' => 'Programming',
  'Dev.to' => 'Programming',
  'freeCodeCamp' => 'Programming',
  'LogRocket' => 'Programming',
  'SitePoint' => 'Programming',
  'The GitHub Blog' => 'Programming',
  'Stack Overflow Blog' => 'Programming',
  'InfoQ' => 'Programming',
  
  # Photography
  'PetaPixel' => 'Photography',
  'Fstoppers' => 'Photography',
  'DPReview' => 'Photography',
  'Colossal' => 'Photography',
  'Bored Panda' => 'Photography',
}

puts "Categorizing entries by source..."

# Get all feeds
feeds = conn.exec("SELECT id, title FROM feeds")

feeds.each do |feed|
  category = CATEGORY_MAP[feed['title']]
  if category
    result = conn.exec_params(
      "UPDATE entries SET category = $1 WHERE feed_id = $2",
      [category, feed['id']]
    )
    puts "#{feed['title']} → #{category} (#{result.cmd_tuples} entries)"
  else
    puts "#{feed['title']} → (no mapping)"
  end
end

puts "\n" + "="*50
puts "Category distribution:"
conn.exec("SELECT category, COUNT(*) as count FROM entries WHERE category IS NOT NULL GROUP BY category ORDER BY count DESC").each do |row|
  puts "  #{row['category']}: #{row['count']}"
end

uncategorized = conn.exec("SELECT COUNT(*) FROM entries WHERE category IS NULL")[0]['count']
puts "  (uncategorized): #{uncategorized}"

conn.close
