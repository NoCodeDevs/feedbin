class AddAttachmentFileToImports < ActiveRecord::Migration[4.2]
  def self.up
    # Paperclip-style columns (avoid has_attached_file - not loaded in migration context)
    add_column :imports, :file_file_name, :string
    add_column :imports, :file_content_type, :string
    add_column :imports, :file_file_size, :integer
    add_column :imports, :file_updated_at, :datetime
  end

  def self.down
    remove_column :imports, :file_file_name
    remove_column :imports, :file_content_type
    remove_column :imports, :file_file_size
    remove_column :imports, :file_updated_at
  end
end
