namespace :places do
  desc "Import or refresh provinces, counties and hotspots from eBird"
  task import_ebird: :environment do
    result = Places::EbirdImporter.new.call
    puts "Imported #{result[:provinces]} provinces, #{result[:counties]} counties and #{result[:hotspots]} hotspots from eBird"
    skipped = result[:counties_without_geometry]
    puts "Skipped #{skipped.size} counties with no geometry and no hotspot: #{skipped.join(", ")}" if skipped.any?
  end

  desc "Import or refresh cities and towns from GeoNames (run after places:import_ebird)"
  task import_geonames: :environment do
    result = Places::GeonamesImporter.new.call
    puts "Imported #{result[:cities]} cities and towns from GeoNames"
  end
end
