namespace :etch do
  desc 'Clean stale clients and old results out of database'
  task :dbclean, [:hours] => [:environment] do |t, args|
    Rake::Task['etch:dbclean:clients'].invoke(args.hours)
    Rake::Task['etch:dbclean:results'].invoke(args.hours)
  end
  
  namespace :dbclean do
    desc 'Clean stale clients out of database'
    task :clients, [:hours] => [:environment] do |t, args|
      if args.hours
        Client.find(:all, :conditions => ['updated_at < ?', args.hours.to_i.hours.ago]).each do |client|
          puts "Deleting #{client.name}"
          client.destroy
        end
      end
    end
    
    desc 'Clean older results out of database'
    task :results, [:hours] => [:environment] do |t, args|
      if args.hours
        Result.find(:all, :conditions => ['created_at < ?', args.hours.to_i.hours.ago]).each do |result|
          puts "Deleting result"
          result.destroy
        end
      end
    end
  end
end

