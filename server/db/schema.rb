# This file is auto-generated from the current state of the database. Instead of editing this file, 
# please use the migrations feature of Active Record to incrementally modify your database, and
# then regenerate this schema definition.
#
# Note that this schema.rb definition is the authoritative source for your database schema. If you need
# to create the application database on another system, you should be using db:schema:load, not running
# all the migrations from scratch. The latter is a flawed and unsustainable approach (the more migrations
# you'll amass, the slower it'll run and the greater likelihood for issues).
#
# It's strongly recommended to check this file into your version control system.

ActiveRecord::Schema.define(:version => 20081003164106) do

  create_table "clients", :force => true do |t|
    t.string   "name",       :null => false
    t.integer  "status"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  add_index "clients", ["status"], :name => "index_clients_on_status"
  add_index "clients", ["name"], :name => "index_clients_on_name", :unique => true

  create_table "etch_configs", :force => true do |t|
    t.integer  "client_id",  :null => false
    t.string   "file",       :null => false
    t.text     "config",     :null => false
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  add_index "etch_configs", ["file"], :name => "index_etch_configs_on_file"
  add_index "etch_configs", ["client_id"], :name => "index_etch_configs_on_client_id"

  create_table "facts", :force => true do |t|
    t.integer  "client_id",  :null => false
    t.string   "key",        :null => false
    t.text     "value",      :null => false
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  add_index "facts", ["key"], :name => "index_facts_on_key"
  add_index "facts", ["client_id"], :name => "index_facts_on_client_id"

  create_table "originals", :force => true do |t|
    t.integer  "client_id",  :null => false
    t.string   "file",       :null => false
    t.string   "sum",        :null => false
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  add_index "originals", ["file"], :name => "index_originals_on_file"
  add_index "originals", ["client_id"], :name => "index_originals_on_client_id"

  create_table "results", :force => true do |t|
    t.integer  "client_id",  :null => false
    t.string   "file",       :null => false
    t.boolean  "success",    :null => false
    t.text     "message",    :null => false
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  add_index "results", ["file"], :name => "index_results_on_file"
  add_index "results", ["client_id"], :name => "index_results_on_client_id"

end
