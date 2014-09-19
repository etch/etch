class Fact < ActiveRecord::Base
  belongs_to :client

  validates_presence_of :client, :key
end
