# This class stores numbers with multiple decimal points, a format
# commonly used for version numbers.  For example '2.5.1'.
class Version
  include Comparable
  
  def initialize(version)
    @version = version
  end
  
  def to_s
    @version
  end
  
  def <=>(other)
    ourfields = @version.split('.')
    otherfields = other.to_s.split('.')
    # Array conveniently implements <=>
    ourfields <=> otherfields
  end
end
