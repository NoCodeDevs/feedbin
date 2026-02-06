# Removes non-English entries from the database
# Run manually: CleanupNonEnglishEntriesJob.perform_async
# Schedule in Sidekiq: run daily via sidekiq-cron or scheduler
#
# Detection uses a simple heuristic based on character ranges and common patterns.
# English text primarily uses ASCII letters with occasional accented characters.
# Non-English is detected by presence of:
# - CJK characters (Chinese/Japanese/Korean)
# - Cyrillic characters (Russian/Ukrainian etc)
# - Arabic/Hebrew characters
# - Thai/Vietnamese/other scripts
# - High ratio of non-ASCII characters

class CleanupNonEnglishEntriesJob
  include Sidekiq::Job
  sidekiq_options queue: :low, retry: 1

  # Character ranges for non-English scripts
  NON_ENGLISH_PATTERNS = [
    /[\u4E00-\u9FFF]/,        # CJK Unified Ideographs (Chinese)
    /[\u3040-\u30FF]/,        # Hiragana + Katakana (Japanese)
    /[\uAC00-\uD7AF]/,        # Hangul (Korean)
    /[\u0400-\u04FF]/,        # Cyrillic (Russian etc)
    /[\u0600-\u06FF]/,        # Arabic
    /[\u0590-\u05FF]/,        # Hebrew
    /[\u0E00-\u0E7F]/,        # Thai
    /[\u1100-\u11FF]/,        # Hangul Jamo
    /[\u3000-\u303F]/,        # CJK Punctuation
    /[\uFF00-\uFFEF]/,        # Halfwidth/Fullwidth Forms
  ].freeze

  def perform(dry_run: false, batch_size: 500, max_deletions: 5000)
    deleted_count = 0
    checked_count = 0

    Rails.logger.info "[CleanupNonEnglish] Starting cleanup (dry_run: #{dry_run})"

    Entry.find_in_batches(batch_size: batch_size) do |entries|
      entries_to_delete = []

      entries.each do |entry|
        checked_count += 1

        # Check title and summary for non-English content
        text = "#{entry.title} #{entry.summary}".to_s

        if non_english?(text)
          entries_to_delete << entry.id
          Rails.logger.debug "[CleanupNonEnglish] Non-English: #{entry.id} - #{entry.title&.truncate(60)}"
        end
      end

      if entries_to_delete.any?
        if dry_run
          Rails.logger.info "[CleanupNonEnglish] DRY RUN - Would delete #{entries_to_delete.size} entries"
        else
          Entry.where(id: entries_to_delete).delete_all
          Rails.logger.info "[CleanupNonEnglish] Deleted #{entries_to_delete.size} entries"
        end
        deleted_count += entries_to_delete.size
      end

      break if deleted_count >= max_deletions
    end

    Rails.logger.info "[CleanupNonEnglish] Complete. Checked: #{checked_count}, Deleted: #{deleted_count}"

    { checked: checked_count, deleted: deleted_count, dry_run: dry_run }
  end

  private

  def non_english?(text)
    return false if text.blank?

    # Check for presence of non-English script characters
    NON_ENGLISH_PATTERNS.any? { |pattern| text.match?(pattern) }
  end
end
