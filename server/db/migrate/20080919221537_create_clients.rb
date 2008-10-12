class CreateClients < ActiveRecord::Migration
  def self.up
    create_table :clients do |t|
      t.string :name, :null => false
      t.integer :status
      t.timestamps
    end
    add_index :clients, :name, :unique => true
    add_index :clients, :status
  end

  def self.down
    drop_table :clients
  end
end
