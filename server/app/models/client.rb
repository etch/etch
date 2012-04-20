class Client < ActiveRecord::Base
  attr_accessible :name, :status, :message

  has_many :facts, :dependent => :destroy
  has_many :originals, :dependent => :destroy
  has_many :etch_configs, :dependent => :destroy
  has_many :results, :dependent => :destroy

  validates_presence_of :name
  validates_uniqueness_of :name
  validates_numericality_of :status, :only_integer => true, :allow_nil => true

  scope :healthy, lambda { where("status = 0 AND updated_at > ?", 24.hours.ago) }
  scope :broken, lambda { where("status != 0 AND status != 200 AND updated_at > ?", 24.hours.ago) }
  scope :disabled, lambda { where("status = 200 AND updated_at > ?", 24.hours.ago) }
  scope :stale, lambda { where("updated_at <= ?", 24.hours.ago) }
end
