require_relative "../../lib/ai_enhancer"

class DeepDivesController < ApplicationController
  skip_before_action :authorize
  skip_before_action :verify_authenticity_token

  # GET /deep-dive/:topic
  def show
    @topic = CGI.unescape(params[:topic].to_s)
    return render json: { error: "No topic" }, status: 400 if @topic.blank?

    # Check cache first
    cache_key = "deep_dive:#{@topic.parameterize}"
    @deep_dive = Rails.cache.fetch(cache_key, expires_in: 2.hours) do
      generate_deep_dive(@topic)
    end

    respond_to do |format|
      format.html { render layout: false }
      format.json { render json: @deep_dive }
    end
  end

  private

  def generate_deep_dive(topic)
    # Get all articles matching the topic from last 14 days
    entries = search_entries(topic, days: 14, limit: 100)

    return empty_deep_dive(topic) if entries.size < 3

    # Group entries by date for timeline
    entries_by_date = entries.group_by { |e| (e.published || e.created_at).to_date }
                             .sort_by { |date, _| -date.to_time.to_i }

    # Prepare articles for AI analysis
    articles = entries.map do |e|
      {
        id: e.id,
        title: e.title,
        source: e.feed&.title,
        summary: ActionController::Base.helpers.strip_tags(e.summary.to_s)[0..500],
        content: ActionController::Base.helpers.strip_tags(e.content.to_s)[0..800],
        url: e.url,
        image: e.processed_image,
        published: e.published
      }
    end

    # Generate AI-powered deep dive content
    enhancer = AIEnhancer.new
    ai_analysis = enhancer.generate_deep_dive(topic, articles)

    # Build timeline with daily summaries
    timeline = entries_by_date.first(14).map do |date, day_entries|
      {
        date: date.iso8601,
        date_label: format_date(date),
        article_count: day_entries.size,
        headlines: day_entries.first(3).map { |e| { title: e.title, url: e.url, source: e.feed&.title } }
      }
    end

    # Source breakdown
    sources = entries.group_by { |e| e.feed&.title }
                     .map { |source, arts| { name: source, count: arts.size } }
                     .sort_by { |s| -s[:count] }
                     .first(10)

    # Calculate trend (compare recent 3 days to earlier)
    recent_count = entries_by_date.first(3).sum { |_, arts| arts.size }
    earlier_count = entries_by_date.drop(3).first(3).sum { |_, arts| arts.size }
    trend = if earlier_count == 0
              "new"
            elsif recent_count > earlier_count * 1.5
              "rising"
            elsif recent_count < earlier_count * 0.5
              "falling"
            else
              "stable"
            end

    # Daily counts for sparkline (14 days)
    sparkline = 14.times.map do |i|
      date = i.days.ago.to_date
      entries_by_date.find { |d, _| d == date }&.last&.size || 0
    end.reverse

    {
      topic: topic,
      generated_at: Time.current.iso8601,
      article_count: entries.size,
      summary: ai_analysis[:summary],
      key_points: ai_analysis[:key_points],
      key_players: ai_analysis[:key_players],
      timeline: timeline,
      sources: sources,
      trend: trend,
      sparkline: sparkline,
      key_articles: ai_analysis[:key_articles],
      related_topics: ai_analysis[:related_topics],
      sentiment: ai_analysis[:sentiment]
    }
  end

  def empty_deep_dive(topic)
    {
      topic: topic,
      generated_at: Time.current.iso8601,
      article_count: 0,
      summary: nil,
      key_points: [],
      key_players: [],
      timeline: [],
      sources: [],
      trend: "insufficient_data",
      sparkline: [],
      key_articles: [],
      related_topics: [],
      sentiment: nil,
      error: "Not enough articles to generate a deep dive. Try a more popular topic."
    }
  end

  def search_entries(topic, days: 14, limit: 100)
    words = topic.downcase.gsub(/[^\w\s]/, ' ').split.reject { |w| w.length < 2 }
    return Entry.none if words.empty?

    sanitized = words.map { |w| "#{w}:*" }.join(' & ')

    Entry.includes(:feed)
         .where("published > ?", days.days.ago)
         .where(
           "to_tsvector('english', coalesce(title, '') || ' ' || coalesce(summary, '')) @@ to_tsquery('english', ?)",
           sanitized
         )
         .order(published: :desc)
         .limit(limit)
  rescue
    # Fallback to ILIKE
    words = topic.downcase.gsub(/[^\w\s]/, ' ').split.reject { |w| w.length < 2 }
    conditions = words.map { "title ILIKE ? OR summary ILIKE ?" }
    values = words.flat_map { |w| ["%#{w}%", "%#{w}%"] }

    Entry.includes(:feed)
         .where("published > ?", days.days.ago)
         .where(conditions.join(' AND '), *values)
         .order(published: :desc)
         .limit(limit)
  end

  def format_date(date)
    if date == Date.current
      "Today"
    elsif date == Date.current - 1
      "Yesterday"
    elsif date > 7.days.ago.to_date
      date.strftime("%A")
    else
      date.strftime("%b %-d")
    end
  end
end
