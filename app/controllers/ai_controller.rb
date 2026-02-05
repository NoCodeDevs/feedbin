require_relative '../../lib/ai_enhancer'

class AiController < ApplicationController
  skip_before_action :authorize
  skip_before_action :verify_authenticity_token

  def chat
    question = params[:q].to_s.strip
    return render json: { error: "No question provided" }, status: 400 if question.blank?
    return render json: { error: "No API key configured. Add ANTHROPIC_API_KEY or OPENAI_API_KEY to .env" }, status: 503 unless api_key_present?

    # Get relevant articles for context
    context_articles = search_relevant_articles(question)
    
    enhancer = AIEnhancer.new
    answer = enhancer.answer_question(
      question,
      context_articles.map { |e| article_context(e) }
    )

    render json: {
      answer: answer,
      sources: context_articles.first(5).map { |e| { title: e.title, url: e.url, source: e.feed&.title } },
      provider: enhancer.provider_name
    }
  rescue => e
    render json: { error: e.message }, status: 500
  end

  def trends
    return render json: { error: "No API key configured" }, status: 503 unless api_key_present?

    recent = Entry.includes(:feed).order(published: :desc).limit(100)
    
    enhancer = AIEnhancer.new
    trends = enhancer.extract_trends(recent.map { |e| { title: e.title } })

    render json: { trends: trends, provider: enhancer.provider_name }
  rescue => e
    render json: { error: e.message }, status: 500
  end

  def digest
    return render json: { error: "No API key configured" }, status: 503 unless api_key_present?

    period = params[:period] || "today"
    
    articles = case period
    when "today"
      Entry.includes(:feed).where("published > ?", 24.hours.ago).order(published: :desc).limit(30)
    when "week"
      Entry.includes(:feed).where("published > ?", 7.days.ago).order(published: :desc).limit(50)
    else
      Entry.includes(:feed).order(published: :desc).limit(30)
    end

    enhancer = AIEnhancer.new
    digest_content = enhancer.generate_digest(
      articles.map { |e| article_context(e) },
      period: period
    )

    render json: { digest: digest_content, article_count: articles.count, provider: enhancer.provider_name }
  rescue => e
    render json: { error: e.message }, status: 500
  end

  def analyze
    entry = Entry.find(params[:id])
    return render json: { error: "No API key configured" }, status: 503 unless api_key_present?

    enhancer = AIEnhancer.new
    analysis = enhancer.analyze_article(entry.title, entry.summary || entry.content)

    if analysis
      entry.update(
        ai_summary: analysis["tldr"],
        ai_insights: analysis["insights"],
        category: analysis["category"],
        complexity: analysis["complexity"],
        reading_time_minutes: analysis["reading_minutes"]
      )
    end

    render json: analysis || { error: "Analysis failed" }
  rescue => e
    render json: { error: e.message }, status: 500
  end

  private

  def api_key_present?
    ENV['ANTHROPIC_API_KEY'].present? || ENV['OPENAI_API_KEY'].present?
  end

  def search_relevant_articles(question)
    keywords = question.downcase.scan(/\b\w{3,}\b/) - %w[the and for are how what why when where which about]
    
    return Entry.includes(:feed).order(published: :desc).limit(10) if keywords.empty?

    conditions = keywords.first(5).map { "(title ILIKE ? OR summary ILIKE ?)" }.join(" OR ")
    values = keywords.first(5).flat_map { |k| ["%#{k}%", "%#{k}%"] }

    Entry.includes(:feed)
         .where(conditions, *values)
         .order(published: :desc)
         .limit(15)
  end

  def article_context(entry)
    {
      title: entry.title,
      source: entry.feed&.title,
      summary: ActionController::Base.helpers.strip_tags(entry.summary.to_s)[0..400],
      url: entry.url,
      published: entry.published
    }
  end
end
