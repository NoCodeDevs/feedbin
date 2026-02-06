require_relative "../../lib/one_feed/promptable_feed"
require_relative "../../lib/ai_enhancer"

class SearchController < ApplicationController
  skip_before_action :authorize
  skip_before_action :verify_authenticity_token

  CATEGORIES = %w[AI/ML Programming Security DevOps Web Mobile Data Business Science Design Culture News Tutorial Opinion]

  def smart_feed
    begin
      if rate_limited?(20, 1.hour)
        respond_to do |format|
          format.html { render plain: "Too many requests. Try again later.", status: :too_many_requests }
          format.json { render json: { error: "Too many requests" }, status: :too_many_requests }
        end
        return
      end
    rescue RedisClient::CannotConnectError, Errno::ENOENT
      # Redis unavailable (e.g. dev without Redis): skip rate limiting
    end

    prompt = params[:prompt].to_s.strip
    @feed_id = params[:feed_id].presence
    service = OneFeed::PromptableFeed.new(prompt: prompt, feed_id: @feed_id)
    @entries = service.entries
    @prompt = prompt
    @smart_feed_unavailable = prompt.present? && !service.api_key_present?
    @sources = sources_with_counts

    respond_to do |format|
      format.html { render :smart_feed, layout: false }
      format.json { render json: { prompt: @prompt, entries: @entries.map { |e| entry_json(e) } } }
    end
  end

  PER_PAGE = 30

  def index
    @query = params[:q].to_s.strip
    @category = params[:category]
    @feed_id = params[:feed_id].presence
    @categories = CATEGORIES
    @sources = sources_with_counts
    @trending_topics = Rails.cache.fetch("trending_topics", expires_in: 1.hour) { trending_topics_with_sparklines }
    @page = [params[:page].to_i, 1].max

    scope = if @query.present?
      search_entries_scope(@query, @category)
    elsif @category.present?
      Entry.includes(:feed)
           .where(with_complete_image)
           .where("categories @> ?", [@category].to_json)
           .order(published: :desc)
    else
      Entry.includes(:feed)
           .where(with_complete_image)
           .order(published: :desc)
    end
    scope = scope.where(feed_id: @feed_id) if @feed_id.present?
    @entries = scope.paginate(page: @page, per_page: PER_PAGE)
    @total_count = @entries.total_entries
    @entries_by_day = @entries.group_by { |e| (e.published || e.created_at).to_date }.sort_by { |date, _| -date.to_time.to_i }

    respond_to do |format|
      format.html do
        if params[:partial]
          render partial: "entries_grouped", layout: false
        else
          render layout: false
        end
      end
      format.json { render json: { entries: @entries.map { |e| entry_json(e) }, total: @total_count, page: @page } }
    end
  end

  def ai_search
    query = params[:q].to_s.strip
    return render json: { error: "No query" }, status: 400 if query.blank?

    # Use AI to understand the query and generate search terms
    search_terms = ai_understand_query(query)

    entries = search_entries_smart(search_terms)

    render json: {
      interpreted_as: search_terms[:interpretation],
      results: entries.map { |e| entry_json(e) }
    }
  end

  def ask
    question = params[:q].to_s.strip
    return render json: { error: "No question provided" }, status: 400 if question.blank?

    unless ENV['ANTHROPIC_API_KEY'] || ENV['OPENAI_API_KEY']
      return render json: { error: "AI features require an API key" }, status: 503
    end

    # Get recent entries (last 48 hours) to answer from
    entries = Entry.includes(:feed)
                   .where("published > ?", 48.hours.ago)
                   .where("image->>'processed_url' IS NOT NULL AND image->>'original_url' IS NOT NULL AND image->>'width' IS NOT NULL AND image->>'height' IS NOT NULL")
                   .order(published: :desc)
                   .limit(50)

    if entries.empty?
      return render json: { answer: "No recent articles found to answer your question.", sources: [] }
    end

    # Prepare context for the AI
    context_articles = entries.map do |e|
      {
        id: e.id,
        title: e.title,
        source: e.feed&.title,
        summary: ActionController::Base.helpers.strip_tags(e.summary.to_s)[0..500],
        url: e.url
      }
    end

    enhancer = AIEnhancer.new
    answer = enhancer.answer_question(question, context_articles)

    # Extract mentioned sources from the answer
    sources = context_articles.select do |a|
      answer.include?(a[:source].to_s) || answer.include?(a[:title].to_s[0..30])
    end.first(5).map do |a|
      { title: a[:title], source: a[:source], url: a[:url], id: a[:id] }
    end

    render json: { answer: answer, sources: sources }
  rescue => e
    Rails.logger.error "Ask error: #{e.message}"
    render json: { error: "Failed to process question" }, status: 500
  end

  private

  def search_entries_scope(query, category = nil)
    sanitized = query.gsub(/[^\w\s]/, ' ').split.map { |w| "#{w}:*" }.join(' & ')
    scope = Entry.includes(:feed).where("image->>'processed_url' IS NOT NULL AND image->>'original_url' IS NOT NULL AND image->>'width' IS NOT NULL AND image->>'height' IS NOT NULL")
    scope = scope.where("categories @> ?", [category].to_json) if category.present?
    scope.where(
      "to_tsvector('english', coalesce(title, '') || ' ' || coalesce(summary, '')) @@ to_tsquery('english', ?)",
      sanitized
    ).order(published: :desc)
  rescue
    scope = Entry.includes(:feed).where("image->>'processed_url' IS NOT NULL AND image->>'original_url' IS NOT NULL AND image->>'width' IS NOT NULL AND image->>'height' IS NOT NULL")
    scope = scope.where("categories @> ?", [category].to_json) if category.present?
    scope.where("title ILIKE ? OR summary ILIKE ?", "%#{query}%", "%#{query}%").order(published: :desc)
  end

  def search_entries(query, category = nil)
    search_entries_scope(query, category).limit(50)
  end

  def search_entries_smart(terms)
    conditions = []
    values = []

    if terms[:keywords].present?
      terms[:keywords].each do |kw|
        conditions << "(title ILIKE ? OR summary ILIKE ?)"
        values << "%#{kw}%" << "%#{kw}%"
      end
    end

    if terms[:category].present? && CATEGORIES.include?(terms[:category])
      conditions << "categories @> ?"
      values << [terms[:category]].to_json
    end

    return Entry.none if conditions.empty?

    Entry.includes(:feed)
         .where("image->>'processed_url' IS NOT NULL AND image->>'original_url' IS NOT NULL AND image->>'width' IS NOT NULL AND image->>'height' IS NOT NULL")
         .where(conditions.join(' AND '), *values)
         .order(published: :desc)
         .limit(30)
  end

  def ai_understand_query(query)
    return { keywords: query.split, interpretation: query } unless ENV['ANTHROPIC_API_KEY'] || ENV['OPENAI_API_KEY']

    begin
      enhancer = AIEnhancer.new
      prompt = <<~PROMPT
        Parse this search query for a tech/programming blog feed:
        "#{query}"

        Extract:
        1. Key search terms (technical terms, names, concepts)
        2. Category if mentioned (one of: #{CATEGORIES.join(', ')})
        3. A plain interpretation of what the user wants

        Return ONLY valid JSON: {"keywords": ["term1", "term2"], "category": "Category or null", "interpretation": "Looking for..."}
      PROMPT

      result = enhancer.chat(prompt, system: "You are a JSON-only responder. Output valid JSON with no markdown formatting.")
      json_match = result.match(/\{.*\}/m)
      if json_match
        parsed = JSON.parse(json_match[0])
        return {
          keywords: parsed["keywords"] || query.split,
          category: parsed["category"],
          interpretation: parsed["interpretation"] || query
        }
      end
    rescue => e
      Rails.logger.error "AI search error: #{e.message}"
    end

    { keywords: query.split, interpretation: query }
  end

  def with_complete_image
    "image->>'processed_url' IS NOT NULL AND image->>'processed_url' != '' AND image->>'original_url' IS NOT NULL AND image->>'width' IS NOT NULL AND image->>'height' IS NOT NULL"
  end

  def entry_json(entry)
    {
      id: entry.id,
      title: entry.title,
      url: entry.url,
      summary: ActionController::Base.helpers.strip_tags(entry.summary.to_s)[0..200],
      category: entry.category,
      feed: entry.feed&.title,
      published: entry.published,
      image_url: entry.image_url
    }
  end

  def sources_with_counts(since: 24.hours.ago)
    since_time = since.is_a?(ActiveSupport::Duration) ? since.ago : since
    Feed.joins(:entries)
        .where("entries.published > ?", since_time)
        .where("entries.image->>'processed_url' IS NOT NULL AND entries.image->>'processed_url' != ''")
        .group("feeds.id", "feeds.title")
        .select("feeds.id, feeds.title, COUNT(entries.id) AS entries_count")
        .order("entries_count DESC")
        .limit(100)
  end

  def trending_topics_with_sparklines
    return @trending_topics_cache if defined?(@trending_topics_cache)

    # Get entries grouped by day for the past 7 days
    days = 7
    entries_by_day = {}
    days.times do |i|
      date = i.days.ago.to_date
      entries_by_day[date.to_s] = Entry
        .where("DATE(published) = ?", date)
        .where(with_complete_image)
        .pluck(:title)
    end

    # Use AI to extract topics
    return [] unless ENV["ANTHROPIC_API_KEY"] || ENV["OPENAI_API_KEY"]

    enhancer = AIEnhancer.new
    topics = enhancer.extract_trending_topics(entries_by_day, limit: 8)

    # Calculate sparkline data for each topic
    topics.map do |topic|
      keywords = topic["keywords"] || [topic["name"]]
      pattern = keywords.map { |k| Regexp.escape(k) }.join("|")
      regex = /#{pattern}/i

      # Count matches per day
      daily_counts = days.times.map do |i|
        date = i.days.ago.to_date.to_s
        titles = entries_by_day[date] || []
        titles.count { |t| t =~ regex }
      end.reverse # oldest first for sparkline

      total = daily_counts.sum
      next if total < 2 # Skip topics with very few matches

      {
        name: topic["name"],
        emoji: topic["emoji"] || "",
        keywords: keywords,
        total: total,
        sparkline: daily_counts,
        trend: calculate_trend(daily_counts)
      }
    end.compact.sort_by { |t| -t[:total] }.first(8)
  rescue => e
    Rails.logger.error "Trending topics error: #{e.message}"
    []
  end

  def calculate_trend(daily_counts)
    return "stable" if daily_counts.size < 3
    recent = daily_counts.last(3).sum
    earlier = daily_counts.first(3).sum
    if recent > earlier * 1.5
      "rising"
    elsif recent < earlier * 0.5
      "falling"
    else
      "stable"
    end
  end
end
