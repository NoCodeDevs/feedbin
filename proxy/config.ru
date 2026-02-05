# Proxy for Feedkit: receives requests with X-Proxy-Host, fetches via ScraperAPI, returns body.
# Deploy to Fly.io, Railway, or a second Heroku app. Set SCRAPERAPI_KEY in env.
# Then in main app: FEEDKIT_PROXY_HOST=https://your-proxy.fly.dev
#                   FEEDKIT_PROXIED_HOSTS=daringfireball.net,feeds.kottke.org

require "rack"
require "http"

proxy = lambda do |env|
  host = env["HTTP_X_PROXY_HOST"]
  unless host
    return [400, { "Content-Type" => "text/plain" }, ["Missing X-Proxy-Host header"]]
  end

  api_key = ENV["SCRAPERAPI_KEY"]
  unless api_key
    return [500, { "Content-Type" => "text/plain" }, ["SCRAPERAPI_KEY not configured"]]
  end

  path = env["PATH_INFO"] || "/"
  path += "?#{env["QUERY_STRING"]}" if env["QUERY_STRING"] && !env["QUERY_STRING"].empty?
  target_url = "https://#{host}#{path}"

  scraper_url = "http://api.scraperapi.com?api_key=#{api_key}&url=#{URI.encode_www_form_component(target_url)}"

  response = HTTP.timeout(30).get(scraper_url)
  body = response.body.to_s

  [response.status.to_i, { "Content-Type" => response.content_type&.mime_type || "application/xml" }, [body]]
rescue HTTP::Error, StandardError => e
  [502, { "Content-Type" => "text/plain" }, ["Proxy error: #{e.message}"]]
end

run proxy
