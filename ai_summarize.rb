#!/usr/bin/env ruby
# AI-powered article summarization using Anthropic Claude or OpenAI
# Usage: ANTHROPIC_API_KEY=sk-... bundle exec ruby ai_summarize.rb

require 'pg'
require 'json'

ANTHROPIC_KEY = ENV['ANTHROPIC_API_KEY']
OPENAI_KEY = ENV['OPENAI_API_KEY']

unless ANTHROPIC_KEY || OPENAI_KEY
  puts "ERROR: Please set ANTHROPIC_API_KEY or OPENAI_API_KEY"
  puts "  export ANTHROPIC_API_KEY=sk-ant-..."
  puts "  OR"
  puts "  export OPENAI_API_KEY=sk-..."
  exit 1
end

if ANTHROPIC_KEY
  require 'anthropic'
  client = Anthropic::Client.new(api_key: ANTHROPIC_KEY)
  provider = "Claude"
else
  require 'openai'
  client = OpenAI::Client.new(access_token: OPENAI_KEY)
  provider = "GPT-4"
end

conn = PG.connect(host: 'localhost', port: 5433, dbname: 'feedbin_development', user: 'art4')

CATEGORIES = %w[Tech News Gaming Business Design Culture Science AI/ML Programming Photography]

def call_ai(client, provider, prompt)
  if provider == "Claude"
    response = client.messages.create(
      model: "claude-sonnet-4-20250514",
      max_tokens: 500,
      system: "You are a JSON-only responder. Output valid JSON with no markdown or explanation.",
      messages: [{ role: "user", content: prompt }]
    )
    response.content.first.text
  else
    response = client.chat(
      parameters: {
        model: "gpt-4o-mini",
        messages: [
          { role: "system", content: "You are a JSON-only responder." },
          { role: "user", content: prompt }
        ],
        temperature: 0.3,
        max_tokens: 500
      }
    )
    response.dig("choices", 0, "message", "content")
  end
end

# Get entries without AI summaries
entries = conn.exec("SELECT id, title, LEFT(summary, 2000) as summary FROM entries WHERE ai_summary IS NULL ORDER BY published DESC LIMIT 100")
puts "="*60
puts "AI ARTICLE SUMMARIZATION (#{provider})"
puts "="*60
puts "Processing #{entries.count} articles...\n\n"

processed = 0
errors = 0

entries.each_with_index do |entry, i|
  begin
    title = entry['title'] || 'Untitled'
    text = (entry['summary'] || '').gsub(/<[^>]+>/, ' ').gsub(/\s+/, ' ').strip[0..1500]
    
    if text.length < 50
      puts "[#{i+1}] SKIP: #{title[0..40]}... (too short)"
      next
    end

    prompt = <<~PROMPT
      Analyze this article:
      Title: #{title}
      Content: #{text}
      
      Return ONLY valid JSON:
      {"tldr": "One sentence summary (max 100 chars)", "reading_minutes": number}
    PROMPT

    print "[#{i+1}] #{title[0..45]}... "
    
    result = call_ai(client, provider, prompt)
    json_match = result.match(/\{.*\}/m)
    
    if json_match
      data = JSON.parse(json_match[0])
      
      conn.exec_params(
        "UPDATE entries SET ai_summary = $1, reading_time_minutes = $2 WHERE id = $3",
        [data["tldr"], data["reading_minutes"].to_i, entry['id']]
      )
      
      puts "OK"
      processed += 1
    else
      puts "PARSE ERROR"
      errors += 1
    end
  rescue => e
    puts "ERROR: #{e.message[0..40]}"
    errors += 1
  end
  
  sleep 0.5 # Rate limiting
end

puts "\n" + "="*60
puts "COMPLETE: #{processed} summarized, #{errors} errors"
puts "="*60

conn.close
