namespace :etch do
  desc 'Clean stale clients out of database'
  task :dbclean, [:hours] => [:environment] do |t, args|
    if args.hours
      Client.find(:all, :conditions => ['updated_at < ?', args.hours.to_i.hours.ago]).each do |client|
        puts "Deleting #{client.name}"
        client.destroy
      end
    end
  end
end

