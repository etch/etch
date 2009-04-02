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
    # Convert anything like '.5' to '0.5'
    # '.5'.split('.') returns ['', '5']
    [ourfields, otherfields].each do |fields|
      if fields[0] == ''
        fields[0] = '0'
      end
    end
    # Pad with zeros so that '1' == '1.0', etc.
    if ourfields.length != otherfields.length
      larger = [ourfields.length, otherfields.length].max
      # For the longer number this depends on something like (3...1).each
      # doing nothing.  That currently works, but is not documented behavior.
      (ourfields.length...larger).each { ourfields << '0' }
      (otherfields.length...larger).each { otherfields << '0' }
    end
    # Convert fields of all digits from string to number to get a numeric
    # rather than string comparison.  This ensures that 5.9 < 5.10
    ourfields.map! { |field| if field =~ /^\d+$/ then field.to_i else field end }
    otherfields.map! { |field| if field =~ /^\d+$/ then field.to_i else field end }
    # Array conveniently implements <=>
    ourfields <=> otherfields
  end
end
