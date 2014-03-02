class ChangeConfigToBlob < ActiveRecord::Migration
  def up
    change_column :etch_configs, :config, :blob
  end
  def down
    change_column :etch_configs, :config, :text
  end
end
