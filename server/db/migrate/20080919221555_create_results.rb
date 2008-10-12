class CreateResults < ActiveRecord::Migration
  def self.up
    create_table :results do |t|
      t.integer :client_id, :null => false
      t.string :file, :null => false
      t.boolean :success, :null => false
      t.text :message, :null => false
      t.timestamps
    end
    add_index :results, :client_id
    add_index :results, :file
  end

  def self.down
    drop_table :results
  end
end
