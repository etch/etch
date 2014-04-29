require 'zlib'

class EtchConfig < ActiveRecord::Base
  attr_accessible :client, :client_id, :file, :config

  belongs_to :client

  validates_presence_of :client, :file, :config

  def config=(config)
    write_attribute(:config, Zlib::Deflate.deflate(config))
  end
  def config
    begin
      if read_attribute(:config)
        Zlib::Inflate.inflate(read_attribute(:config))
      else
        read_attribute(:config)
      end
    rescue Zlib::DataError
      read_attribute(:config)
    end
  end
end
