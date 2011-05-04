require 'rake/testtask'

# rake test
Rake::TestTask.new do |t|
  # If the user hasn't already set the xmllib environment variable then set it
  # to use nokogiri so that the tests involving DTD validation are run.
  if !ENV['xmllib']
    ENV['xmllib'] = 'nokogiri'
  end
  
  t.verbose = true
end
