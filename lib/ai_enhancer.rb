require 'json'

class AIEnhancer
  CATEGORIES = %w[Tech News Gaming Business Design Culture Science AI/ML Programming Photography]

  def initialize
    @anthropic_key = ENV['ANTHROPIC_API_KEY']
    @openai_key = ENV['OPENAI_API_KEY']
    
    if @anthropic_key
      require 'anthropic'
      @client = Anthropic::Client.new(api_key: @anthropic_key)
      @provider = :anthropic
    elsif @openai_key
      require 'openai'
      @client = OpenAI::Client.new(access_token: @openai_key)
      @provider = :openai
    else
      raise "No API key found. Set ANTHROPIC_API_KEY or OPENAI_API_KEY"
    end
  end

  def chat(prompt, system: nil)
    if @provider == :anthropic
      response = @client.messages.create(
        model: "claude-sonnet-4-20250514",
        max_tokens: 1024,
        system: system || "You are a helpful assistant.",
        messages: [{ role: "user", content: prompt }]
      )
      response.content.first.text
    else
      messages = []
      messages << { role: "system", content: system } if system
      messages << { role: "user", content: prompt }
      
      response = @client.chat(
        parameters: {
          model: "gpt-4o-mini",
          messages: messages,
          temperature: 0.3,
          max_tokens: 1024
        }
      )
      response.dig("choices", 0, "message", "content")
    end
  end

  # Generate TL;DR summary and key insights for an article
  def analyze_article(title, content, max_content: 3000)
    text = content.to_s.gsub(/<[^>]+>/, ' ').gsub(/\s+/, ' ').strip[0..max_content]
    
    prompt = <<~PROMPT
      Analyze this article:
      Title: #{title}
      Content: #{text}
      
      Return ONLY valid JSON (no markdown, no explanation):
      {
        "tldr": "One sentence summary (max 100 chars)",
        "insights": ["Key insight 1", "Key insight 2", "Key insight 3"],
        "category": "ONE of: #{CATEGORIES.join(', ')}",
        "complexity": "beginner OR intermediate OR advanced",
        "reading_minutes": number
      }
    PROMPT

    result = chat(prompt, system: "You are a JSON-only responder. Output valid JSON with no markdown formatting.")
    json_match = result.match(/\{.*\}/m)
    json_match ? JSON.parse(json_match[0]) : nil
  rescue => e
    puts "Error analyzing article: #{e.message}"
    nil
  end

  # Answer questions about articles
  def answer_question(question, context_articles, conversation_history: [])
    context = context_articles.map do |a|
      "Title: #{a[:title]}\nSource: #{a[:source]}\nSummary: #{a[:summary].to_s[0..400]}\nURL: #{a[:url]}"
    end.join("\n\n---\n\n")

    system = <<~SYSTEM
      You are a helpful assistant that answers questions about news articles.
      Answer based on the provided context. Cite sources with [Source Name].
      If you can't find relevant info, say so. Be concise but informative.
    SYSTEM

    prompt = "Context articles:\n#{context}\n\nQuestion: #{question}"
    
    chat(prompt, system: system)
  rescue => e
    "Sorry, I encountered an error: #{e.message}"
  end

  # Get trending topics across recent articles
  def extract_trends(articles, limit: 8)
    texts = articles.map { |a| "- #{a[:title]}" }.join("\n")
    
    prompt = <<~PROMPT
      These are recent article titles:
      #{texts}
      
      Identify the #{limit} most prominent trending topics/themes.
      Return ONLY valid JSON: {"trends": [{"topic": "Topic Name", "count": number, "description": "brief description"}]}
    PROMPT

    result = chat(prompt, system: "You are a JSON-only responder.")
    json_match = result.match(/\{.*\}/m)
    json_match ? JSON.parse(json_match[0])["trends"] : []
  rescue => e
    puts "Error extracting trends: #{e.message}"
    []
  end

  # Filter and rank entries by a natural-language prompt (for promptable feed).
  # entries: array of hashes with :id, :title, :summary (optional :feed)
  # Returns array of entry ids in order of relevance (most first).
  def filter_and_rank_entries(entries, prompt)
    return entries.map { |e| e[:id] } if entries.size <= 1

    list = entries.map do |e|
      summary = (e[:summary].to_s).gsub(/<[^>]+>/, " ").gsub(/\s+/, " ").strip[0..300]
      feed = e[:feed].to_s[0..40]
      "[#{e[:id]}] #{e[:title].to_s[0..120]}#{" | #{summary}" if summary.present?}#{" | feed: #{feed}" if feed.present?}"
    end.join("\n")

    system_msg = "You are a JSON-only responder. Output valid JSON with no markdown or explanation."
    user_msg = <<~PROMPT
      The user wants to see articles about: "#{prompt}"

      Below are recent articles. Return a JSON object with one key "entry_ids": an array of entry ids, in order of relevance (most relevant first).

      Rules:
      - Include ONLY articles that are clearly about or meaningfully related to "#{prompt}" (e.g. the topic appears in the title, summary, or is the main subject).
      - Exclude articles that are not about this topic. Do not include weak or tangential matches.
      - Use the number in [brackets] as the id. Return only ids from the list below.
      - If no articles are clearly about this topic, return {"entry_ids": []}.

      Articles:
      #{list}

      Example: {"entry_ids": [42, 17, 99]}
    PROMPT

    result = chat(user_msg, system: system_msg)
    json_match = result&.match(/\{.*\}/m)
    return entries.map { |e| e[:id] } unless json_match

    data = JSON.parse(json_match[0])
    ids = data["entry_ids"].to_a.map(&:to_i)
    # Preserve only ids that exist in our list; append any we didn't return so nothing is dropped
    entry_ids = entries.map { |e| e[:id] }
    ids &= entry_ids
    ids + (entry_ids - ids)
  rescue => e
    Rails.logger.error "OneFeed filter_and_rank error: #{e.message}"
    entries.map { |e| e[:id] }
  end

  # Generate a digest/newsletter summary
  def generate_digest(articles, period: "today")
    articles_text = articles.first(20).map do |a|
      "- #{a[:title]} (#{a[:source]})"
    end.join("\n")

    prompt = <<~PROMPT
      Create a brief digest of #{period}'s top articles:
      
      #{articles_text}
      
      Write 2-3 paragraphs highlighting the biggest stories and key themes.
      Be engaging and informative. Use markdown formatting.
    PROMPT

    chat(prompt, system: "You are a tech news editor writing a daily digest.")
  rescue => e
    "Unable to generate digest: #{e.message}"
  end

  def provider_name
    @provider == :anthropic ? "Claude" : "GPT-4"
  end
end
