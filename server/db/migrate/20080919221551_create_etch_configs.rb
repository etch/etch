class CreateEtchConfigs < ActiveRecord::Migration
  def self.up
    create_table :etch_configs do |t|
      t.integer :client_id, :null => false
      t.string :file, :null => false
      t.text :config, :null => false
      t.timestamps
    end
    add_index :etch_configs, :client_id
    add_index :etch_configs, :file
  end

  def self.down
    drop_table :etch_configs
  end
end
