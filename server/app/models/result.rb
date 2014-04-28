class Result < ActiveRecord::Base
  attr_accessible :client, :client_id, :file, :success, :message

  belongs_to :client

  validates_presence_of :client, :file, :message
  validates_inclusion_of :success, :in => [true, false]
end
