namespace :places do
  desc "Import or refresh provinces, counties and hotspots from eBird"
  task import_ebird: :environment do
    result = Places::EbirdImporter.new.call
    puts "Imported #{result[:provinces]} provinces, #{result[:counties]} counties and #{result[:hotspots]} hotspots from eBird"
    skipped = result[:counties_without_geometry]
    puts "Skipped #{skipped.size} counties with no geometry and no hotspot: #{skipped.join(", ")}" if skipped.any?
  end
end
