# http://www.caliban.org/ruby/rubyguide.shtml#warnings
class Silently
  def self.silently(&block)
    warn_level = $VERBOSE
    $VERBOSE = nil
    result = block.call
    $VERBOSE = warn_level
    result
  end
end

