namespace :taxonomy do
  desc "Import or refresh the canonical eBird taxonomy and the featured species groups"
  task import: :environment do
    result = Taxonomy::EbirdImporter.new.call
    puts "Imported #{result[:taxa]} taxa (eBird taxonomy #{result[:version]})"
  end
end
