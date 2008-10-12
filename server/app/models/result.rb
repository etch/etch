class Result < ActiveRecord::Base

  belongs_to :client

  validates_presence_of :client, :file, :message
  validates_associated :client
  validates_inclusion_of :success, :in => [true, false]

end
