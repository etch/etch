class Original < ActiveRecord::Base
  attr_accessible :client, :client_id, :file, :sum

  belongs_to :client

  validates_presence_of :client, :file, :sum
  validates_associated :client

end
