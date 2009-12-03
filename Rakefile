require 'rake/testtask'

# rake test
Rake::TestTask.new do |t|
  # If the user hasn't already set the xmllib environment variable then set it
  # to use LibXML so that the tests involving DTD validation are run.
  if !ENV['xmllib']
    ENV['xmllib'] = 'libxml'
  end
  
  t.verbose = true
  #t.pattern = 'test/*.rb'
  t.test_files = Dir.glob('test/*.rb').reject {|test| test =~ /etchtest.rb/}
end
