class CreateFacts < ActiveRecord::Migration
  def self.up
    create_table :facts do |t|
      t.integer :client_id, :null => false
      t.string :key, :null => false
      t.text :value, :null => false
      t.timestamps
    end
    add_index :facts, :client_id
    add_index :facts, :key
  end

  def self.down
    drop_table :facts
  end
end
