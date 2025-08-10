# frozen_string_literal: true
# Bot configurations
require "dotenv/load"
require "fileutils"

module Config
  BASE_DIR = File.expand_path(__dir__)
  DATA_DIR = File.join(BASE_DIR, "data")
  FileUtils.mkdir_p(DATA_DIR)

  # --- Telegram bot ---
  BOT_TOKEN = ENV.fetch("TG_BOT_TOKEN")
  # Allow multiple admin IDs separated by commas
  ADMIN_ID  = ENV.fetch("ADMIN_ID").split(",").map(&:strip)
  TELEGRAM_MAX_CHARS_LIMIT = 4096
  TIMEZONE           = "Europe/Prague"

  # --- RecEngine API ---
  BASE_REC_URL = "http://139.162.133.102:443"

  # --- Weather API ---
  WMO_DESCRIPTIONS = {
    0=>"Clear sky ☀️",1=>"Mainly clear 🌤",2=>"Partly cloudy ⛅",3=>"Overcast ☁️",
    45=>"Fog 🌫",48=>"Depositing rime fog 🌫",
    51=>"Light drizzle 🌦",53=>"Moderate drizzle 🌦",55=>"Dense drizzle 🌧",
    56=>"Light freezing drizzle 🌧❄️",57=>"Dense freezing drizzle 🌧❄️",
    61=>"Light rain 🌦",63=>"Moderate rain 🌧",65=>"Heavy rain 🌧",
    66=>"Light freezing rain 🌧❄️",67=>"Heavy freezing rain 🌧❄️",
    71=>"Light snow 🌨",73=>"Moderate snow 🌨",75=>"Heavy snow ❄️",
    77=>"Snow grains ❄️",
    80=>"Rain showers 🌦",81=>"Heavy rain showers 🌧",82=>"Violent rain showers 🌧",
    85=>"Snow showers 🌨",86=>"Heavy snow showers ❄️",
    95=>"Thunderstorm ⛈",96=>"Thunderstorm with hail ⛈",99=>"Heavy thunderstorm with hail ⛈"
  }.freeze

  CLEAR_CODES          = [0,1,2,3].freeze
  FOG_CODES            = [45,48].freeze
  DRIZZLE_CODES        = [51,53,55,56,57].freeze
  RAIN_CODES           = [61,63,65,80,81,82].freeze
  FREEZING_RAIN_CODES  = [66,67].freeze
  SNOW_CODES           = [71,73,75,77,85,86].freeze
  THUNDER_CODES        = [95,96,99].freeze

  WEATHER_GROUPS = {
    clear: CLEAR_CODES,
    fog: FOG_CODES,
    drizzle: DRIZZLE_CODES,
    rain: RAIN_CODES,
    freezing_rain: FREEZING_RAIN_CODES,
    snow: SNOW_CODES,
    thunder: THUNDER_CODES
  }.freeze

  WEATHER_NOTES = {
    clear: "🌞 Enjoy the day!",
    fog: "🌫 Drive carefully!",
    drizzle: "🌦 You might need a light umbrella.",
    rain: "☔ Take an umbrella!",
    freezing_rain: "❄️⚠️ Roads might be icy — walk carefully.",
    snow: "❄️ Wear something warm!",
    thunder: "⚡ Stay indoors if possible!"
  }.freeze

  # --- Music API ---
  SPOTIFY_MY_PLAYLIST_URL = "https://open.spotify.com/playlist/6C1vRrYVdJWzLrLhEGN0vJ"
  API_side_link_music = "https://api.reccobeats.com/v1/track/recommendation"
  SPOTIFY_FILE = File.join(DATA_DIR, "playlist_tracks.json")
  MUSIC_FILE = File.join(DATA_DIR, "free_beats_music.json")
  DEFAULT_AMOUNT = 2
  MUSIC_SEEDS = %w[
    https://open.spotify.com/track/5QmdK8QFbY8TLVKPuJzexD?si=334d297ff87c4bea
    https://open.spotify.com/track/4sUTagdmyuyAxd7RvbygpQ?si=650d11e1dafe4bf0
    https://open.spotify.com/track/6gSalwEvVQfSFiqgwfyITp?si=363a3b5c4fcf408a
    https://open.spotify.com/track/5QmdK8QFbY8TLVKPuJzexD?si=bd45a23a83854c85
    https://open.spotify.com/track/5i1lwW1eG8qy2K0M6zxn7B?si=4dc5855927bd4e10
    https://open.spotify.com/track/5UWwZ5lm5PKu6eKsHAGxOk?si=b7f9b790d64c4834
    https://open.spotify.com/track/3lwSNFtP1p9n88HkCGNty8?si=c944adaa0cc74eb3
    https://open.spotify.com/track/0wvIGFIgbyz4JNwQhZgTv2?si=185e562c692344d6
    https://open.spotify.com/track/2nKMYmI6vWX99OnKeZSrfk?si=6d92fb3f4cd34175
    https://open.spotify.com/track/2LtWGOsyqmd88HCHX3hNn6?si=e541182e09eb4230
  ]
  MUSIC_DEFAULT_FEATURES = {
    "acousticness"     => 0.10,
    "danceability"     => 0.20,
    "energy"           => 0.10,
    "instrumentalness" => 0.10,
    "liveness"         => 0.15,
    "speechiness"      => 0.05,
    "valence"          => 0.25,
    "mode"             => 1,
    "popularity"       => 1,
    "featureWeight"    => 3
  }

  # --- Users database ---
  USERS_CSV  = File.join(DATA_DIR, "users.csv")

  # --- Broadcast settings ---
  BROADCAST_CRON = "0,10 10,13,16,19,22 * * *"

  # --- 420on.cz news parser ---
  # Where to scrape from
  BASE_NEWS_URL = ENV.fetch("BASE_NEWS_URL", "https://420on.cz")
  NEWS_PAGE_URL = ENV.fetch("NEWS_PAGE_URL", "https://420on.cz") # or specific listing page

  # Where to persist the parsed JSON
  NEWS_FILE     = File.join(DATA_DIR, "420on_news.json")

  # How many to keep/show
  NEWS_COUNT    = Integer(ENV.fetch("NEWS_COUNT", "3"))

  # Cron for 06:00, 12:00, 18:00, 22:00 in your configured TIMEZONE
  NEWS_CRON     = ENV.fetch("NEWS_CRON", "0 6,12,18,22 * * *")

end
