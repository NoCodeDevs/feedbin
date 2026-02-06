module FeedCrawler
  class Receiver
    include Sidekiq::Worker
    sidekiq_options queue: :parse

    def perform(data)
      feed = Feed.find(data["feed"]["id"])
      if data["entries"].present?
        receive_entries(data["entries"], feed)
      end
      feed.update(data["feed"])
    end

    def receive_entries(items, feed)
      # Look up existing entries by public_id and by (feed_id, url) to avoid duplicates
      public_ids = items.map { |entry| entry["public_id"] }
      entries_by_public_id = Entry.where(public_id: public_ids).index_by(&:public_id)
      urls = items.filter_map { |item| item["url"] }.compact
      entries_by_url = urls.any? ? Entry.where(feed_id: feed.id, url: urls).index_by(&:url) : {}
      items.each do |item|
        entry = entries_by_public_id[item["public_id"]] || (item["url"].present? && entries_by_url[item["url"]])
        update = item.delete("update")
        if entry
          EntryUpdate.create!(item, entry)
        else
          create_entry(item, feed)
        end
      rescue ActiveRecord::RecordNotUnique
        # Ignore
      rescue => exception
        unless exception.message =~ /Validation failed/i
          message = update ? "update" : "create"
          ErrorService.notify(
            error_class: "Receiver#" + message,
            error_message: "Entry #{message} failed",
            parameters: {feed_id: feed.id, item: item, exception: exception, backtrace: exception.backtrace}
          )
          Sidekiq.logger.info "Entry Error: feed=#{feed.id} exception=#{exception.inspect}"
        end
      end
    end

    def create_entry(item, feed)
      if alternate_exists?(item)
        Librato.increment("entry.alternate_exists")
      elsif !has_potential_image?(item)
        Librato.increment("entry.skipped_no_image")
        Sidekiq.logger.info "Skipping entry without image=#{item["public_id"]}"
      else
        entry = if item["url"].present?
          feed.entries.find_or_initialize_by(url: item["url"])
        else
          feed.entries.find_or_initialize_by(public_id: item["public_id"])
        end
        entry.assign_attributes(item)
        entry.save!
        Librato.increment("entry.create") if entry.previously_new_record?
        Sidekiq.logger.info "Creating entry=#{item["public_id"]}" if entry.previously_new_record?
      end
    end

    def has_potential_image?(item)
      content = item["content"].to_s
      # Check for img tags in content
      return true if content.include?("<img")
      # Check for figure/picture elements
      return true if content.include?("<figure") || content.include?("<picture")
      # Check for media/enclosure data
      data = item["data"] || {}
      return true if data["itunes_image"].present?
      return true if data["media_content"].present?
      return true if data["enclosure_url"].present?
      false
    end

    def alternate_exists?(item)
      if item["data"] && item["data"]["public_id_alt"]
        FeedbinUtils.public_id_exists?(item["data"]["public_id_alt"])
      end
    end
  end
end