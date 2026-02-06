class CustomFeedsController < ApplicationController
  skip_before_action :authorize
  skip_before_action :verify_authenticity_token

  CATEGORIES = %w[AI/ML Programming Security DevOps Web Gaming Business Science Design Culture News Tutorial]

  CATEGORY_MAPPING = {
    "AI/ML" => ["ai", "artificial intelligence", "machinelearning", "deeplearning", "agentic ai", "claude"],
    "Programming" => ["programming", "software", "coding", "python", "rust", "go"],
    "Security" => ["security", "cybersecurity"],
    "DevOps" => ["devops", "docker", "kubernetes"],
    "Web" => ["webdev", "web", "javascript", "frontend", "react"],
    "Gaming" => ["games", "gaming", "videogames"],
    "Business" => ["business", "startup", "biz & it", "product"],
    "Science" => ["science", "research"],
    "Design" => ["design", "ui", "ux"],
    "Culture" => ["culture", "entertainment", "funny"],
    "News" => ["news"],
    "Tutorial" => ["tutorial", "howto"]
  }

  PER_PAGE = 30

  # GET /feed - Feed Builder UI
  def index
    @categories = CATEGORIES
    @selected = []
    @sources = sources_list
    render layout: false
  end

  # GET /feed/:slug - Show custom feed
  def show
    @slug = params[:slug]
    @selected_categories = @slug.split("+").map { |c| CGI.unescape(c) }.select { |c| CATEGORIES.include?(c) }

    return redirect_to feed_builder_path if @selected_categories.empty?

    @page = [params[:page].to_i, 1].max

    # Build query for multiple categories
    conditions = @selected_categories.map { |cat| "(#{category_filter_sql(cat)})" }

    @entries = Entry.includes(:feed)
                    .where(with_complete_image)
                    .where(conditions.join(" OR "))
                    .order(published: :desc)
                    .paginate(page: @page, per_page: PER_PAGE)

    @total_count = @entries.total_entries
    @entries_by_day = @entries.group_by { |e| (e.published || e.created_at).to_date }
                              .sort_by { |date, _| -date.to_time.to_i }

    @feed_url = request.original_url
    @categories = CATEGORIES

    respond_to do |format|
      format.html do
        if params[:partial]
          render partial: "search/entries_grouped", layout: false
        else
          render layout: false
        end
      end
      format.json do
        render json: {
          categories: @selected_categories,
          entries: @entries.map { |e| entry_json(e) },
          total: @total_count,
          page: @page
        }
      end
    end
  end

  private

  def with_complete_image
    "image->>'processed_url' IS NOT NULL AND image->>'processed_url' != '' AND image->>'original_url' IS NOT NULL AND image->>'width' IS NOT NULL AND image->>'height' IS NOT NULL"
  end

  def category_filter_sql(category)
    db_categories = CATEGORY_MAPPING[category] || [category.downcase]
    conditions = db_categories.map do |cat|
      quoted = ActiveRecord::Base.connection.quote(cat.downcase)
      "EXISTS (SELECT 1 FROM jsonb_array_elements_text(categories) elem WHERE LOWER(elem) = #{quoted})"
    end
    conditions.join(" OR ")
  end

  def sources_list
    Feed.joins(:entries)
        .where("entries.published > ?", 7.days.ago)
        .group("feeds.id", "feeds.title")
        .select("feeds.id, feeds.title, COUNT(entries.id) AS entries_count")
        .order("entries_count DESC")
        .limit(50)
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
      image_url: entry.processed_image
    }
  end
end
