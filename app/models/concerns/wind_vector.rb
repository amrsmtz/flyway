# Wind stored as mean eastward (u) and northward (v) speeds of the air, in
# km/h. Averaging components, not compass directions, keeps a north wind
# that veers between 350° and 10° from averaging to a south wind.
module WindVector
  extend ActiveSupport::Concern

  COMPASS = %w[N NNE NE ENE E ESE SE SSE S SSW SW WSW W WNW NW NNW].freeze

  # level is "925hpa" (about 750 m up) or "10m".
  def wind_speed_kmh(level = "925hpa")
    u, v = wind_components(level)
    Math.hypot(u, v) if u
  end

  # Direction the wind comes from, in degrees clockwise from north.
  def wind_from_degrees(level = "925hpa")
    u, v = wind_components(level)
    (Math.atan2(-u, -v) * 180 / Math::PI) % 360 if u
  end

  def wind_from_compass(level = "925hpa")
    degrees = wind_from_degrees(level)
    COMPASS[((degrees + 11.25) / 22.5).floor % 16] if degrees
  end

  # Speed at which the wind pushes a bird flying toward heading_degrees:
  # positive is a tailwind, negative a headwind.
  def tailwind_kmh(heading_degrees, level = "925hpa")
    u, v = wind_components(level)
    return unless u

    heading = heading_degrees * Math::PI / 180
    u * Math.sin(heading) + v * Math.cos(heading)
  end

  private

  def wind_components(level)
    u = self["wind_u_#{level}"]
    v = self["wind_v_#{level}"]
    [ u, v ] if u && v
  end
end
