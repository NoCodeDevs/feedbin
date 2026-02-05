defaults = {connect_timeout: 5, timeout: 5}
defaults[:url] = ENV["REDIS_URL"] if ENV["REDIS_URL"]
# Heroku Redis (rediss://) uses TLS with a cert that fails default verification
defaults[:ssl_params] = {verify_mode: OpenSSL::SSL::VERIFY_NONE} if defaults[:url]&.start_with?("rediss://")

$redis = {}.tap do |hash|
  options2 = defaults.dup
  if ENV["REDIS_URL_PUBLIC_IDS"] || ENV["REDIS_URL_CACHE"]
    options2[:url] = ENV["REDIS_URL_PUBLIC_IDS"] || ENV["REDIS_URL_CACHE"]
  end
  options2[:ssl_params] = {verify_mode: OpenSSL::SSL::VERIFY_NONE} if options2[:url]&.start_with?("rediss://")
  hash[:refresher] = ConnectionPool.new(size: 10) { Redis.new(options2) }
end
