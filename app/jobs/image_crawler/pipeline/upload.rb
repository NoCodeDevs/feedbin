module ImageCrawler
  module Pipeline
    class Upload
      include Sidekiq::Worker
      include SidekiqHelper

      sidekiq_options queue: local_queue("crawl"), retry: false

      def perform(image_hash)
        @image = Image.new(image_hash)
        @image.storage_url = upload
        @image.send_to_feedbin

        DownloadCache.save(@image)
        Sidekiq.logger.info "Upload: id=#{@image.id} original_url=#{@image.original_url} storage_url=#{@image.storage_url} width=#{@image.width} height=#{@image.height}"
      ensure
        File.unlink(@image.processed_path) if @image&.processed_path && File.exist?(@image.processed_path)
      end

      def upload
        if ENV["CLOUDINARY_URL"].present?
          upload_to_cloudinary
        else
          upload_to_s3
        end
      end

      def upload_to_cloudinary
        require "cloudinary"
        result = Cloudinary::Uploader.upload(
          @image.processed_path,
          public_id: @image.id,
          folder: "feedbin"
        )
        result["secure_url"]
      end

      def upload_to_s3
        File.open(@image.processed_path) do |file|
          options = STORAGE.dup
          options = options.merge(region: @image.preset.region) unless @image.preset.region.nil?
          response = Fog::Storage.new(options).put_object(@image.bucket, @image.image_name, file, @image.storage_options)

          klass = Rails.env.development? ? URI::HTTP : URI::HTTPS

          uri = klass.build(
            host: response.data[:host],
            path: response.data[:path]
          )

          if Rails.env.development?
            uri.port = response.data[:port]
          end

          uri.to_s
        end
      end
    end
  end
end
