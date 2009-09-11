# http://drawohara.com/post/117643208/ruby-integer-max-and-integer-min
class Integer
  N_BYTES = [42].pack('i').size
  N_BITS = N_BYTES * 8
  MAX = 2 ** (N_BITS - 2) - 1
  MIN = -MAX - 1
end
