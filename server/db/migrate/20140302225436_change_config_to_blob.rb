class ChangeConfigToBlob < ActiveRecord::Migration
  def up
    change_column :etch_configs, :config, :binary, :limit => 16.megabyte
  end
  def down
    change_column :etch_configs, :config, :text
  end
end
