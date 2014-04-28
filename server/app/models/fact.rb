class Fact < ActiveRecord::Base
  attr_accessible :client, :client_id, :key, :value

  belongs_to :client

  validates_presence_of :client, :key
end
