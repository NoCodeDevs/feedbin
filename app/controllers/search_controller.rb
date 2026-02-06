require "openai"
require_relative "../../lib/one_feed/promptable_feed"

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
    @page = [params[:page].to_i, 1].max

    scope = if @query.present?
      search_entries_scope(@query, @category)
    elsif @category.present?
      Entry.includes(:feed)
           .where("? = ANY(categories)", @category)
           .order(published: :desc)
    else
      Entry.includes(:feed)
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

  private

  def search_entries_scope(query, category = nil)
    sanitized = query.gsub(/[^\w\s]/, ' ').split.map { |w| "#{w}:*" }.join(' & ')
    scope = Entry.includes(:feed).where.not(image_url: [nil, ''])
    scope = scope.where(category: category) if category.present?
    scope.where(
      "to_tsvector('english', coalesce(title, '') || ' ' || coalesce(summary, '')) @@ to_tsquery('english', ?)",
      sanitized
    ).order(published: :desc)
  rescue
    scope = Entry.includes(:feed).where.not(image_url: [nil, ''])
    scope = scope.where(category: category) if category.present?
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
      conditions << "category = ?"
      values << terms[:category]
    end

    return Entry.none if conditions.empty?

    Entry.includes(:feed)
         .where.not(image_url: [nil, ''])
         .where(conditions.join(' AND '), *values)
         .order(published: :desc)
         .limit(30)
  end

  def ai_understand_query(query)
    return { keywords: query.split, interpretation: query } unless ENV['OPENAI_API_KEY']

    begin
      client = OpenAI::Client.new(access_token: ENV['OPENAI_API_KEY'])
      
      response = client.chat(
        parameters: {
          model: "gpt-4o-mini",
          messages: [{
            role: "user",
            content: <<~PROMPT
              Parse this search query for a tech/programming blog feed:
              "#{query}"
              
              Extract:
              1. Key search terms (technical terms, names, concepts)
              2. Category if mentioned (one of: #{CATEGORIES.join(', ')})
              3. A plain interpretation of what the user wants
              
              Return JSON: {"keywords": ["term1", "term2"], "category": "Category or null", "interpretation": "Looking for..."}
            PROMPT
          }],
          temperature: 0.2,
          max_tokens: 150
        }
      )

      result = response.dig("choices", 0, "message", "content")
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
        .group("feeds.id", "feeds.title")
        .select("feeds.id, feeds.title, COUNT(entries.id) AS entries_count")
        .order("entries_count DESC")
        .limit(100)
  end
end
