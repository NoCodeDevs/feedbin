class RemoveFileFromImports < ActiveRecord::Migration[4.2]
  def self.up
    remove_column :imports, :file_file_name, :string
    remove_column :imports, :file_content_type, :string
    remove_column :imports, :file_file_size, :integer
    remove_column :imports, :file_updated_at, :datetime
  end

  def self.down
    add_column :imports, :file_file_name, :string
    add_column :imports, :file_content_type, :string
    add_column :imports, :file_file_size, :integer
    add_column :imports, :file_updated_at, :datetime
  end
end
