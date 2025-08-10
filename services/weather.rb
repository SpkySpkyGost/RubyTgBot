# frozen_string_literal: true
require "httparty"
require "json"
require "openssl"
require_relative "../config"

module Weather
  GEOCODE_URL  = "https://geocoding-api.open-meteo.com/v1/search"
  FORECAST_URL = "https://api.open-meteo.com/v1/forecast"

  # Force non-persistent connections to avoid EOFs on some hosts
  HTTP_OPTS = {
    timeout: 10,
    open_timeout: 5,
    read_timeout: 5,
    headers: {
      "User-Agent" => "ruby-weather-bot/1.0",
      "Connection" => "close"
    }
  }.freeze

  RETRYABLE = [
    OpenSSL::SSL::SSLError,
    Net::OpenTimeout, Net::ReadTimeout,
    Errno::ECONNRESET, EOFError, SocketError
  ].freeze

  module_function

  # --- small helper for resilient GET -> JSON ---
  def get_json(url, query: nil, tries: 3, opts: {})
    attempt = 0
    begin
      attempt += 1
      res = HTTParty.get(url, query: query, **HTTP_OPTS.merge(opts))
      return parse_json(res) if res.code == 200
      warn "[weather] HTTP #{res.code} for #{url} #{query && "(#{query})"}"
      nil
    rescue *RETRYABLE => e
      warn "[weather] #{e.class}: #{e.message} (attempt #{attempt}/#{tries})"
      sleep(1.2 * attempt)
      retry if attempt < tries
      nil
    end
  end

  def parse_json(res)
    return nil unless res&.body
    res.parsed_response.is_a?(String) ? JSON.parse(res.body) : res.parsed_response
  rescue JSON::ParserError => e
    warn "[weather] bad JSON: #{e.message}"
    nil
  end

  # --- API calls ---
  def geocode(city)
    q = { name: city, count: 1, language: "en", format: "json" }
    if (json = get_json(GEOCODE_URL, query: q))
      if (m = json.dig("results", 0))
        return { name: m["name"], lat: m["latitude"], lon: m["longitude"], country: m["country"] }
      end
    end

    # Fallback: Nominatim (OSM)
    nomi = "https://nominatim.openstreetmap.org/search"
    q2 = { q: city, format: "json", limit: 1 }
    opts = { headers: { "User-Agent" => "ruby-weather-bot/1.0 (contact: you@example.com)", "Connection" => "close" } }
    if (json2 = get_json(nomi, query: q2, opts: opts))
      if json2.is_a?(Array) && (m = json2.first)
        return { name: m["display_name"], lat: m["lat"].to_f, lon: m["lon"].to_f, country: "" }
      end
    end

    nil
  end

  def forecast(lat, lon)
    params = {
      latitude: lat, longitude: lon,
      current: "temperature_2m,relative_humidity_2m,apparent_temperature,weather_code,wind_speed_10m"
    }
    if (json = get_json(FORECAST_URL, query: params))
      return json["current"]
    end
    nil
  end

  # --- classification helpers (uses Config) ---
  def describe_code(code)
    (Config::WMO_DESCRIPTIONS[code] rescue nil) || "Unknown weather"
  end

  def group_for(code)
    # returns :clear, :fog, :drizzle, :rain, :freezing_rain, :snow, :thunder, or nil
    (Config::WEATHER_GROUPS.find { |_k, codes| codes.include?(code) }&.first rescue nil)
  end

  def note_for_group(group)
    (Config::WEATHER_NOTES[group] rescue nil) || ""
  end

  # --- formatter ---
  # cur is the parsed JSON object from the "current" field in the API response
  def format_weather(place, cur)
    t    = cur["temperature_2m"]
    ap   = cur["apparent_temperature"]
    rh   = cur["relative_humidity_2m"]
    ws   = cur["wind_speed_10m"]
    code = cur["weather_code"]

    desc  = describe_code(code)
    group = group_for(code)
    tip   = note_for_group(group)

    header = "#{place[:name]} 🌍"
    line1  = "#{desc}#{tip.empty? ? "" : " — #{tip}"}"
    line2  = "🌡 Temperature: #{t}°C (feels like #{ap}°C)"
    line3  = "💧 Humidity: #{rh}% · 🌬 Wind: #{ws} m/s"
    line4  = "🗺 WMO code: #{code}"

    [header, line1, line2, line3, line4].join("\n")
  end
end
