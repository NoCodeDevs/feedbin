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

CATEGORIES = %w[AI/ML Programming Security DevOps Web Mobile Data Business Science Design Culture News Tutorial Opinion]

# Get entries that haven't been analyzed yet
entries = conn.exec("SELECT id, title, LEFT(summary, 2000) as summary FROM entries WHERE ai_summary IS NULL ORDER BY published DESC LIMIT 200")
puts "Analyzing #{entries.count} entries with AI..."
puts "This will use approximately #{entries.count * 0.002} USD in API costs.\n\n"

batch_size = 5
processed = 0
errors = 0

entries.to_a.each_slice(batch_size).with_index do |batch, batch_idx|
  puts "Batch #{batch_idx + 1}/#{(entries.count / batch_size.to_f).ceil}..."
  
  batch.each do |entry|
    begin
      title = entry['title'] || 'Untitled'
      text = (entry['summary'] || '').gsub(/<[^>]+>/, ' ').gsub(/\s+/, ' ').strip[0..1500]
      
      # Skip if no real content
      if text.length < 50
        puts "  [SKIP] #{title[0..50]}... (too short)"
        next
      end
      
      response = client.chat(
        parameters: {
          model: "gpt-4o-mini",
          messages: [{
            role: "user",
            content: <<~PROMPT
              Analyze this tech article:
              Title: #{title}
              Content: #{text}
              
              Return JSON:
              {
                "tldr": "One compelling sentence summary (max 100 chars)",
                "insights": ["Key insight 1", "Key insight 2", "Key insight 3"],
                "category": "ONE of: #{CATEGORIES.join(', ')}",
                "complexity": "beginner OR intermediate OR advanced",
                "reading_minutes": number (estimate 200 words/min),
                "entities": {"people": [], "companies": [], "technologies": []}
              }
            PROMPT
          }],
          temperature: 0.3,
          max_tokens: 400
        }
      )

      result = response.dig("choices", 0, "message", "content")
      json_match = result.match(/\{.*\}/m)
      
      if json_match
        data = JSON.parse(json_match[0])
        
        # Validate category
        category = CATEGORIES.include?(data["category"]) ? data["category"] : nil
        complexity = %w[beginner intermediate advanced].include?(data["complexity"]) ? data["complexity"] : nil
        
        conn.exec_params(<<~SQL, [
          data["tldr"],
          JSON.generate(data["insights"] || []),
          category,
          complexity,
          data["reading_minutes"].to_i,
          JSON.generate(data["entities"] || {}),
          entry['id']
        ])
          UPDATE entries SET 
            ai_summary = $1,
            ai_insights = $2,
            category = $3,
            complexity = $4,
            reading_time_minutes = $5,
            entities = $6
          WHERE id = $7
        SQL
        
        puts "  [OK] #{title[0..50]}... → #{category || 'uncategorized'}"
        processed += 1
      end
    rescue => e
      puts "  [ERR] #{entry['title'][0..40]}... - #{e.message[0..50]}"
      errors += 1
    end
    
    sleep 0.3 # Rate limiting
  end
  
  sleep 1 # Batch cooldown
end

puts "\n" + "="*50
puts "COMPLETE!"
puts "  Processed: #{processed}"
puts "  Errors: #{errors}"
puts "="*50

# Show category distribution
puts "\nCategory distribution:"
conn.exec("SELECT category, COUNT(*) as count FROM entries WHERE category IS NOT NULL GROUP BY category ORDER BY count DESC").each do |row|
  puts "  #{row['category']}: #{row['count']}"
end

conn.close
