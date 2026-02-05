#!/usr/bin/env ruby
require 'openai'
require 'pg'
require 'json'

OPENAI_API_KEY = ENV['OPENAI_API_KEY']

unless OPENAI_API_KEY
  puts "ERROR: Please set OPENAI_API_KEY environment variable"
  puts "  export OPENAI_API_KEY=sk-..."
  exit 1
end

client = OpenAI::Client.new(access_token: OPENAI_API_KEY)
conn = PG.connect(host: 'localhost', port: 5433, dbname: 'feedbin_development', user: 'art4')

CATEGORIES = %w[
  AI/ML
  Programming
  Security
  DevOps
  Web
  Mobile
  Data
  Business
  Science
  Design
  Culture
  News
  Tutorial
  Opinion
]

# Get uncategorized entries
entries = conn.exec("SELECT id, title, LEFT(summary, 500) as summary FROM entries WHERE category IS NULL LIMIT 100")
puts "Categorizing #{entries.count} entries..."

batch_size = 10
entries.to_a.each_slice(batch_size).with_index do |batch, batch_idx|
  puts "\nBatch #{batch_idx + 1}..."
  
  # Build prompt with all entries in batch
  entries_text = batch.map.with_index do |entry, i|
    title = entry['title'] || 'Untitled'
    summary = (entry['summary'] || '')[0..200].gsub(/\s+/, ' ')
    "#{i+1}. \"#{title}\" - #{summary}"
  end.join("\n")
  
  prompt = <<~PROMPT
    Categorize each article into ONE of these categories:
    #{CATEGORIES.join(', ')}
    
    Articles:
    #{entries_text}
    
    Return ONLY a JSON array with the category for each article in order.
    Example: ["Programming", "AI/ML", "Security"]
  PROMPT
  
  begin
    response = client.chat(
      parameters: {
        model: "gpt-4o-mini",
        messages: [{ role: "user", content: prompt }],
        temperature: 0.3,
        max_tokens: 200
      }
    )
    
    result = response.dig("choices", 0, "message", "content")
    # Extract JSON array from response
    json_match = result.match(/\[.*\]/m)
    if json_match
      categories = JSON.parse(json_match[0])
      
      batch.each_with_index do |entry, i|
        category = categories[i]
        if category && CATEGORIES.include?(category)
          conn.exec_params("UPDATE entries SET category = $1 WHERE id = $2", [category, entry['id']])
          puts "  #{entry['title'][0..40]}... → #{category}"
        end
      end
    end
  rescue => e
    puts "  Error: #{e.message}"
  end
  
  sleep 0.5 # Rate limiting
end

# Show category distribution
puts "\n\nCategory distribution:"
conn.exec("SELECT category, COUNT(*) as count FROM entries WHERE category IS NOT NULL GROUP BY category ORDER BY count DESC").each do |row|
  puts "  #{row['category']}: #{row['count']}"
end

conn.close
