class EtchConfig < ActiveRecord::Base
  attr_accessible :client, :client_id, :file, :config

  belongs_to :client

  validates_presence_of :client, :file, :config
  validates_associated :client

end
