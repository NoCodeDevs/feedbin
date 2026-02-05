require "sidekiq"
require ::File.expand_path("../../../lib/job_stat", __FILE__)

Sidekiq.strict_args!(false)

# Sidekiq::Extensions.enable_delay!

redis_options = {id: "feedbin-server-#{::Process.pid}"}
redis_options[:ssl_params] = {verify_mode: OpenSSL::SSL::VERIFY_NONE} if ENV["REDIS_URL"]&.start_with?("rediss://")

Sidekiq.configure_server do |config|
  ActiveRecord::Base.establish_connection
  config.server_middleware do |chain|
    chain.add JobStat
  end
  config.redis = redis_options
end

Sidekiq.configure_client do |config|
  config.redis = redis_options.merge(id: "feedbin-client-#{::Process.pid}")
end
