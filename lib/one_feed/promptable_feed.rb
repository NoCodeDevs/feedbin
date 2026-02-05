# Service for the promptable main feed (no login).
# Loads a global pool of recent entries and uses the LLM to filter and rank by prompt.
require_relative "../ai_enhancer"

module OneFeed
  class PromptableFeed
    DEFAULT_LIMIT = 80
    DEFAULT_SINCE = 24.hours

    def initialize(prompt:, limit: DEFAULT_LIMIT, since: DEFAULT_SINCE, feed_id: nil)
      @prompt = prompt.to_s.strip
      @limit = limit.to_i.clamp(1, 150)
      @since = since
      @feed_id = feed_id.presence
    end

    def entries
      since_time = @since.is_a?(ActiveSupport::Duration) ? @since.ago : @since
      base = Entry.includes(:feed)
                  .where("published > ?", since_time)
                  .where.not(image_url: [nil, ''])
                  .order(published: :desc)
                  .limit(@limit)
      base = base.where(feed_id: @feed_id) if @feed_id.present?

      return base.to_a if @prompt.blank?
      return base.to_a unless api_key_present?

      ordered_ids = with_cache { fetch_ordered_ids(base) }
      return [] if ordered_ids.blank?

      Entry.includes(:feed)
           .where(id: ordered_ids)
           .in_order_of(:id, ordered_ids)
           .to_a
    end

    def api_key_present?
      ENV["ANTHROPIC_API_KEY"].present? || ENV["OPENAI_API_KEY"].present?
    end

    private

    def with_cache
      cache_key = "onefeed:#{normalized_prompt}:#{window_key}:#{@feed_id}"
      Rails.cache.fetch(cache_key, expires_in: 30.minutes) { yield }
    end

    def normalized_prompt
      @prompt.downcase.gsub(/\s+/, " ").strip
    end

    def window_key
      Time.current.beginning_of_hour.to_i
    end

    def fetch_ordered_ids(scope)
      list = scope.map do |e|
        {
          id: e.id,
          title: e.title,
          summary: e.summary,
          feed: e.feed&.title
        }
      end
      enhancer = AIEnhancer.new
      enhancer.filter_and_rank_entries(list, @prompt)
    end
  end
end
