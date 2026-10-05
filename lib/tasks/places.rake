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

  desc "Import or refresh curated birding sites and regions from config/gazetteer.yml (run after places:import_ebird)"
  task import_curated: :environment do
    result = Places::CuratedImporter.new.call
    puts "Imported #{result[:sites].size} sites and #{result[:regions].size} regions"

    result[:sites].each do |site|
      hotspots = Place.hotspots.within_km(site.latitude, site.longitude, site.default_radius_km)
      puts format("  %-36s %2d km  %3d hotspots  %7d checklists", site.name, site.default_radius_km, hotspots.count, site.importance)
    end
  end
end
