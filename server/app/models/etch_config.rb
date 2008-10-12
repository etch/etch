class EtchConfig < ActiveRecord::Base

  belongs_to :client

  validates_presence_of :client, :file, :config
  validates_associated :client

end
