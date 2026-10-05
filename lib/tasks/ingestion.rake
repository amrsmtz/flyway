namespace :ingestion do
  desc "Process pending units of a feed for a number of seconds: ingestion:run[ebird,120]"
  task :run, %i[feed seconds] => :environment do |_task, args|
    seconds = (args[:seconds] || 60).to_i
    completed = Ingestion::Runner.new(args.fetch(:feed), time_budget: seconds.seconds).call
    puts "Completed #{completed} units of #{args[:feed]}"
  end

  desc "Show the state of every feed's queue"
  task status: :environment do
    IngestionUnit.group(:feed, :kind, :status).order(:feed, :kind, :status).count.each do |(feed, kind, status), count|
      puts format("%-12s %-12s %-8s %6d", feed, kind, status, count)
    end
    FeedStatus.order(:feed).each do |status|
      puts "#{status.feed}: last success #{status.last_success_at}, latest data #{status.latest_data_at}, " \
           "quota #{status.remaining_quota}, paused until #{status.paused_until || "-"}, last error #{status.last_error || "-"}"
    end
  end
end

namespace :ebird do
  desc "Queue the 12-month eBird backfill for the counties of featured sites"
  task plan_backfill: :environment do
    puts "Queued #{Ebird::Planner.new.plan_backfill} new units"
  end

  desc "Queue the refresh of recent days"
  task plan_live: :environment do
    Ebird::Planner.new.plan_live
    puts "Live units scheduled"
  end
end

namespace :inaturalist do
  desc "Queue the 12-month iNaturalist backfill, one unit per day"
  task plan_backfill: :environment do
    puts "Queued #{Inaturalist::Planner.new.plan_backfill} new units"
  end
end

namespace :weather do
  desc "Create the weather points, then queue 12 months of weather for them"
  task plan_backfill: :environment do
    puts "#{WeatherPoint.sync!} weather points"
    puts "Queued #{OpenMeteo::Planner.new.plan_backfill} new units"
  end
end
