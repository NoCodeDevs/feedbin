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

  # Extract trending topics with search keywords for filtering
  def extract_trending_topics(titles_by_day, limit: 10)
    # titles_by_day: { "2024-01-01" => ["title1", "title2"], ... }
    all_titles = titles_by_day.values.flatten.first(200).map { |t| "- #{t}" }.join("\n")

    prompt = <<~PROMPT
      Analyze these article titles from the past 7 days and identify the #{limit} most prominent trending topics.

      Titles:
      #{all_titles}

      Return ONLY valid JSON:
      {
        "topics": [
          {
            "name": "Short topic name (2-4 words)",
            "keywords": ["keyword1", "keyword2"],
            "emoji": "single relevant emoji"
          }
        ]
      }

      Rules:
      - Topics should be specific (e.g., "OpenAI GPT-5" not just "AI")
      - Keywords should match words likely in article titles
      - Order by prominence/frequency
    PROMPT

    result = chat(prompt, system: "You are a JSON-only responder. Output valid JSON with no markdown.")
    json_match = result&.match(/\{.*\}/m)
    return [] unless json_match

    JSON.parse(json_match[0])["topics"] || []
  rescue => e
    Rails.logger.error "Trending topics error: #{e.message}"
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

  # Summarize a topic with key takeaways and linked articles
  def summarize_topic(topic, articles)
    return { summary: "", takeaways: [], key_articles: [] } if articles.empty?

    articles_text = articles.first(15).map.with_index do |a, i|
      "[#{i}] #{a[:title]} (#{a[:source]}): #{a[:summary].to_s[0..200]}"
    end.join("\n")

    prompt = <<~PROMPT
      Based on these recent articles about "#{topic}", provide:
      1. A concise 2-3 sentence summary of what's happening with this topic
      2. 3-5 key takeaways (bullet points)
      3. The 3 most important article indices to read

      Articles:
      #{articles_text}

      Return ONLY valid JSON:
      {
        "summary": "2-3 sentence overview of what's happening",
        "takeaways": ["Key point 1", "Key point 2", "Key point 3"],
        "key_article_indices": [0, 1, 2]
      }
    PROMPT

    result = chat(prompt, system: "You are a news analyst. Provide insightful summaries. Output valid JSON only, no markdown.")
    json_match = result&.match(/\{.*\}/m)
    return { summary: "", takeaways: [], key_articles: [] } unless json_match

    data = JSON.parse(json_match[0])
    key_indices = data["key_article_indices"] || []
    key_articles = key_indices.map { |i| articles[i] }.compact.map do |a|
      { id: a[:id], title: a[:title], source: a[:source], url: a[:url] }
    end

    {
      summary: data["summary"] || "",
      takeaways: data["takeaways"] || [],
      key_articles: key_articles
    }
  rescue => e
    Rails.logger.error "Summarize topic error: #{e.message}"
    { summary: "", takeaways: [], key_articles: [] }
  end

  # Cluster articles into story groups based on topic similarity
  def cluster_stories(articles, max_clusters: 10)
    return [] if articles.empty?

    titles = articles.map.with_index { |a, i| "[#{i}] #{a[:title]} (#{a[:source]})" }.join("\n")

    prompt = <<~PROMPT
      These are recent news articles. Group them into story clusters - articles covering the same news story or topic.

      Articles:
      #{titles}

      Return ONLY valid JSON with this structure:
      {
        "clusters": [
          {
            "headline": "Main story headline (your summary)",
            "article_indices": [0, 3, 7],
            "topic": "Brief topic description"
          }
        ]
      }

      Rules:
      - Only group articles that are clearly about the SAME specific story/event
      - Single articles with no matches should NOT be included
      - Maximum #{max_clusters} clusters
      - Use the [number] as the index
    PROMPT

    result = chat(prompt, system: "You are a JSON-only responder. Output valid JSON with no markdown.")
    json_match = result&.match(/\{.*\}/m)
    return [] unless json_match

    data = JSON.parse(json_match[0])
    clusters = data["clusters"] || []

    # Map indices back to articles
    clusters.map do |cluster|
      indices = cluster["article_indices"].to_a.map(&:to_i)
      cluster_articles = indices.map { |i| articles[i] }.compact
      next if cluster_articles.size < 2

      {
        headline: cluster["headline"],
        topic: cluster["topic"],
        articles: cluster_articles
      }
    end.compact
  rescue => e
    Rails.logger.error "Story clustering error: #{e.message}"
    []
  end

  # Compare how different sources cover the same story
  def compare_coverage(articles)
    return nil if articles.size < 2

    context = articles.map do |a|
      summary = a[:summary].to_s.gsub(/<[^>]+>/, ' ').gsub(/\s+/, ' ').strip[0..500]
      "Source: #{a[:source]}\nTitle: #{a[:title]}\nSummary: #{summary}"
    end.join("\n\n---\n\n")

    prompt = <<~PROMPT
      These articles cover the same story from different sources. Analyze the coverage:

      #{context}

      Return ONLY valid JSON:
      {
        "summary": "2-3 sentence neutral summary of what happened",
        "perspectives": [
          {"source": "Source Name", "angle": "Their focus/angle in 1 sentence", "tone": "neutral/positive/negative/critical"}
        ],
        "key_differences": "What do sources emphasize differently?",
        "consensus": "What do all sources agree on?"
      }
    PROMPT

    result = chat(prompt, system: "You are a media analyst. Be objective and insightful. Output valid JSON only.")
    json_match = result&.match(/\{.*\}/m)
    return nil unless json_match

    JSON.parse(json_match[0])
  rescue => e
    Rails.logger.error "Coverage comparison error: #{e.message}"
    nil
  end
end
