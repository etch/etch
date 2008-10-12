class CreateOriginals < ActiveRecord::Migration
  def self.up
    create_table :originals do |t|
      t.integer :client_id, :null => false
      t.string :file, :null => false
      t.string :sum, :null => false
      t.timestamps
    end
    add_index :originals, :client_id
    add_index :originals, :file
  end

  def self.down
    drop_table :originals
  end
end
