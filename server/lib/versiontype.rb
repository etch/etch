# This class stores numbers with multiple decimal points, a format
# commonly used for version numbers.  For example '2.5.1'.

class Version
  include Comparable
  
  def initialize(version)
    @version = version.to_s
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
    
    convert_and_split!(ourfields, otherfields)
    
    # Array conveniently implements <=>
    ourfields <=> otherfields
  end
  
  # Private methods below
  private
  
  
  # Loops over two arrays in parallel.  If the entry at a given
  # position in both arrays is numeric it is converted from a string to
  # a number, or if either entry is a mixture of numeric and
  # non-numeric characters then both are split into an array consisting
  # of the numeric and non-numeric components.
  def convert_and_split!(fields0, fields1)
    # Pad the shorter of two arrays with zeros so that both arrays are
    # the same length.  This ensures that '1' == '1.0', etc.
    if fields0.length != fields1.length
      larger = [fields0.length, fields1.length].max
      # For the longer number this depends on something like (3...1).each
      # doing nothing.  That currently works, but is not documented behavior.
      (fields0.length...larger).each { fields0 << '0' }
      (fields1.length...larger).each { fields1 << '0' }
    end
    
    # Squish both arrays together
    bothfields = []
    (0...fields0.length).each { |i| bothfields << [fields0[i], fields1[i]] }
    
    bothfields.map! do |fields|
      # Convert fields of all digits from string to number to get a numeric
      # rather than string comparison.  This ensures that 5.9 < 5.10
      # Unless either start with a zero, as 1.1 != 1.01, but converting
      # 01 to a number turns it into 1.
      if fields[0] =~ /^[1-9]\d*$/ && fields[1] =~ /^[1-9]\d*$/
        fields.map! { |f| f.to_i }
      else
        # If the field is a mixture of numeric and non-numeric
        # characters then split it up into an array of those components
        # so that we compare "naturally".  I.e. 9a < 10a
        # This is similar to the method used by most "natural sort"
        # algorithms that aim to sort file9 above file10.
        if fields[0] =~ /\d\D/ || fields[0] =~ /\D\d/ ||
           fields[1] =~ /\d\D/ || fields[1] =~ /\D\d/
          fields.map! { |f| f.scan(/\d+|\D+/) }
          # Pass back through this method to convert the numeric
          # entries to numbers
          convert_and_split!(fields[0], fields[1])
        end
      end
      fields
    end
    # Unsquish back to separate arrays
    fields0.clear
    fields1.clear
    bothfields.each { |fields| fields0 << fields[0]; fields1 << fields[1] }
  end
end
