class MoveNewsletterTokens < ActiveRecord::Migration[6.0]
  def up
    # MoveTokens job removed/renamed; skip for fresh DB (no users to migrate)
  end

  def down
  end
end
