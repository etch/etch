class Original < ActiveRecord::Base
  belongs_to :client

  validates_presence_of :client, :file, :sum
end
