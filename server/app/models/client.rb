class Client < ActiveRecord::Base

  has_many :facts, :dependent => :destroy
  has_many :originals, :dependent => :destroy
  has_many :etch_configs, :dependent => :destroy
  has_many :results, :dependent => :destroy

  validates_presence_of :name
  validates_uniqueness_of :name
  validates_numericality_of :status, :only_integer => true, :allow_nil => true

end
