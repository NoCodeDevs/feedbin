class FeedRequestsController < ApplicationController
  skip_before_action :authorize
  skip_before_action :verify_authenticity_token

  ENTRY_LIMIT_ON_ADD = 50

  def create
    begin
      if rate_limited?(10, 1.hour)
        return render json: { error: "Too many requests. Try again later." }, status: :too_many_requests
      end
    rescue RedisClient::CannotConnectError, Errno::ENOENT
      # proceed without rate limiting
    end

    url = normalize_feed_url(params[:url].to_s.strip)
    unless url
      return render json: { error: "Please enter a valid http or https URL." }, status: :unprocessable_entity
    end

    response = Feedkit::Request.download(url)
    parsed = response.parse
    final_url = response.url

    if parsed.blank? || parsed.entries.blank?
      return render json: { error: "This URL doesn't appear to be a valid feed or has no entries." }, status: :unprocessable_entity
    end

    existing = Feed.xml.find_by(feed_url: final_url)
    if existing
      return render json: { error: "This feed is already in the directory.", feed_id: existing.id, title: existing.title }, status: :ok
    end

    feed = Feed.create_from_parsed_feed(parsed, entry_limit: ENTRY_LIMIT_ON_ADD)
    render json: { success: true, message: "Feed added.", feed_id: feed.id, title: feed.title }
  rescue => e
    feedkit_error = e.class.name.to_s.start_with?("Feedkit::")
    msg = feedkit_error ? "Could not fetch or parse feed: #{e.message}" : "Something went wrong. Please check the URL and try again."
    Rails.logger.error "FeedRequestsController: #{e.class} #{e.message}"
    render json: { error: msg }, status: :unprocessable_entity
  end

  private

  def normalize_feed_url(url)
    return nil if url.blank?
    uri = Addressable::URI.heuristic_parse(url)
    return nil unless uri&.host.present?
    uri.scheme = "https" if uri.scheme.blank?
    return nil unless %w[http https].include?(uri.scheme.to_s.downcase)
    uri.normalize.to_s
  rescue Addressable::URI::InvalidURIError
    nil
  end
end
