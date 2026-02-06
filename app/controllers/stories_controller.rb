require_relative "../../lib/ai_enhancer"

class StoriesController < ApplicationController
  skip_before_action :authorize
  skip_before_action :verify_authenticity_token

  def index
    @clusters = []
    @comparison = nil
    @selected_cluster_index = params[:cluster].to_i if params[:cluster].present?

    # Get recent entries with complete images
    entries = Entry.includes(:feed)
                   .where("published > ?", 48.hours.ago)
                   .where("image->>'processed_url' IS NOT NULL AND image->>'original_url' IS NOT NULL AND image->>'width' IS NOT NULL AND image->>'height' IS NOT NULL")
                   .order(published: :desc)
                   .limit(100)

    return if entries.empty?

    # Prepare articles for clustering
    articles = entries.map do |e|
      {
        id: e.id,
        title: e.title,
        source: e.feed&.title,
        summary: ActionController::Base.helpers.strip_tags(e.summary.to_s)[0..500],
        url: e.url,
        image: e.processed_image,
        published: e.published
      }
    end

    # Get clusters from AI
    if api_key_present?
      enhancer = AIEnhancer.new
      @clusters = enhancer.cluster_stories(articles)

      # If a specific cluster is selected, get the comparison
      if @selected_cluster_index && @clusters[@selected_cluster_index]
        cluster = @clusters[@selected_cluster_index]
        @comparison = enhancer.compare_coverage(cluster[:articles])
        @selected_cluster = cluster
      end
    end

    respond_to do |format|
      format.html { render layout: false }
      format.json { render json: { clusters: @clusters, comparison: @comparison } }
    end
  end

  def compare
    entry_ids = params[:ids].to_s.split(",").map(&:to_i)
    return render json: { error: "Need at least 2 articles" }, status: 400 if entry_ids.size < 2

    entries = Entry.includes(:feed).where(id: entry_ids)
    articles = entries.map do |e|
      {
        id: e.id,
        title: e.title,
        source: e.feed&.title,
        summary: ActionController::Base.helpers.strip_tags(e.summary.to_s)[0..500],
        url: e.url
      }
    end

    enhancer = AIEnhancer.new
    comparison = enhancer.compare_coverage(articles)

    render json: { comparison: comparison, articles: articles }
  rescue => e
    render json: { error: e.message }, status: 500
  end

  private

  def api_key_present?
    ENV["ANTHROPIC_API_KEY"].present? || ENV["OPENAI_API_KEY"].present?
  end
end
