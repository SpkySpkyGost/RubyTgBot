# stdlib / gems
require "telegram/bot"
require "json"
require_relative "lib/bot/csv_store" # << fix here
require "time"
require "fileutils"
require "rufus-scheduler"
require "net/http"
require "uri"
require "nokogiri"

# app code
require_relative "config"
require_relative "services/news"
require_relative "services/weather"
require_relative "services/spotify"
require_relative "services/music"
require_relative "services/timer"
require_relative "services/buses"
require_relative "lib/bot/bot"   # loads Bot::CSVStore et al

# our modules
require_relative "lib/bot/bot.rb"

# --- Config / constants ---
BOT_TOKEN           = Config::BOT_TOKEN
ADMIN_ID            = Config::ADMIN_ID
DATA_DIR            = Config::DATA_DIR
SPOTIFY_FILE        = Config::SPOTIFY_FILE
MUSIC_FILE          = Config::MUSIC_FILE
USERS_CSV           = Config::USERS_CSV
TELEGRAM_MAX_CHARS  = Config::TELEGRAM_MAX_CHARS_LIMIT
BASE_REC_URL        = Config::BASE_REC_URL
DEFAULT_AMOUNT      = Config::DEFAULT_AMOUNT

KEYBOARD = Telegram::Bot::Types::ReplyKeyboardMarkup.new(
  keyboard: [
    [{ text: "Report" }, { text: "Recommender" }],
    [{ text: "Subscribe" }, { text: "Timer" }],
    [{ text: "Transport" }, { text: "Music" }]
  ],
  resize_keyboard: true,
  one_time_keyboard: false
)

# Ensure CSV exists
unless File.exist?(USERS_CSV)
  CSV.open(USERS_CSV, "w") { |csv| csv << ["user_id", "city", "last_start"] }
end

def main
  Telegram::Bot::Client.run(BOT_TOKEN) do |bot|
    begin
      SpotifyPlaylist.fetch_and_save(out: SPOTIFY_FILE, playlist_url: Config::SPOTIFY_MY_PLAYLIST_URL)
      Music.fetch_recommendations
      News.fetch_and_save(count: Config::NEWS_COUNT)
    rescue => e
      warn "[SETUP] #{e.class}: #{e.message}"
    end

    scheduler = Rufus::Scheduler.new

    scheduler.cron Config::NEWS_CRON, tz: Config::TIMEZONE do
      begin
        News.fetch_and_save(count: Config::NEWS_COUNT)
      rescue => e
        warn "[scheduler] news error: #{e.class}: #{e.message}"
      end
    end

    scheduler.cron Config::BROADCAST_CRON, tz: Config::TIMEZONE do
      begin
        Bot::Broadcast.broadcast_daily_reports(bot)
      rescue => e
        warn "[scheduler] broadcast error: #{e.class}: #{e.message}"
      end
    end

    scheduler.every "1h", tz: Config::TIMEZONE do
      begin
        Array(ADMIN_ID).each do |admin_id|
          Bot::Rec.run_recommender_for(bot, admin_id, admin_id)
        end
      rescue => e
        warn "[scheduler] recommend error: #{e.class}: #{e.message}"
      end
    end

    bot.listen do |update|
      begin
        # Callbacks
        if update.is_a?(Telegram::Bot::Types::CallbackQuery)
          if update.data == "rec_clear"
            chat_id = update.message.chat.id
            Bot::Messaging.clear_recommender_messages(bot, chat_id)
            begin
              bot.api.answer_callback_query(callback_query_id: update.id, text: "Cleared ✅")
            rescue Telegram::Bot::Exceptions::ResponseError => e
              warn "[listen] Failed to answer callback: #{e.class} - #{e.message}"
            end

          elsif update.data == "bus_clear"
            chat_id = update.message.chat.id
            Bot::Transport.clear_transport_messages(bot, chat_id)
            begin
              bot.api.answer_callback_query(callback_query_id: update.id, text: "Cleared ✅")
            rescue Telegram::Bot::Exceptions::ResponseError => e
              warn "[listen] Failed to answer callback: #{e.class} - #{e.message}"
            end
          end
          next
        end

        # Regular messages
        next unless update.is_a?(Telegram::Bot::Types::Message)
        message = update
        #puts message.from.id
        user_id = message.from&.id
        next unless user_id

        Bot::CSVStore.add_user_if_missing(user_id)


        raw_text = (message.text || "").strip
        text     = raw_text.downcase

        # If user is in Transport flow, handle that first
        if Bot::Transport::BUS_FLOW[message.chat.id][:step] != :idle
          handled = Bot::Transport.handle_bus_flow_input(bot, message)
          next if handled
        end

        # Early subscription handler
        if raw_text =~ /^w\s+(.+)/i
          city = Regexp.last_match(1).strip
          Bot::CSVStore.update_city(message.from.id, city)

          place = Weather.geocode(city)
          if place.nil?
            Bot::Messaging.send_message(bot, message.chat.id, "Could not geocode the city.")
            next
          end

          cur = Weather.forecast(place[:lat], place[:lon])
          if cur.nil?
            Bot::Messaging.send_message(bot, message.chat.id, "Weather API is not available.")
            next
          end

          weather_data = Weather.format_weather(place, cur)
          Bot::Messaging.send_message(
            bot, message.chat.id,
            "✅ Subscribed for *#{city}*.\n\n#{weather_data}",
            parse_mode: "Markdown"
          )
          next
        end

        case text
        when "/start", "start"
          if Bot::CSVStore.subscribed?(message.from.id)
            city = Bot::CSVStore.get_user_city(message.from.id)
            Bot::Messaging.send_message(
              bot, message.chat.id,
              "👋 Welcome back!\nYou're subscribed for *#{city}*.\n\n" \
                "Use the buttons below or type `report`.",
              parse_mode: "Markdown"
            )
          else
            Bot::Messaging.send_message(
              bot, message.chat.id,
              "👋 Welcome!\nTo *subscribe* and receive daily reports, set your city:\n" \
                "`w <city>` (e.g. `w London`)\n\n" \
                "After that, you’ll get broadcasts automatically.",
              parse_mode: "Markdown"
            )
          end

        when "subscribe", "/subscribe"
          Bot::Messaging.send_message(
            bot, message.chat.id,
            "To subscribe, send: `w <city>` (e.g., `w London`).",
            parse_mode: "Markdown"
          )

        when "timer", "/timer"
          unless Bot::CSVStore.subscribed?(message.from.id)
            Bot::Messaging.send_message(bot, message.chat.id, "Please subscribe first: `w <city>`", parse_mode: "Markdown")
            next
          end
          Bot::Messaging.send_message(bot, message.chat.id, Timer.message, parse_mode: "Markdown")

        when "recommender", "/recommender"
          if ADMIN_ID.include?(message.from.id.to_s)
            Bot::Messaging.send_message(bot, message.chat.id, "Calling test site...")
            Bot::Rec.run_recommender_for(bot, message.chat.id, message.from.id)
          else
            Bot::Messaging.send_message(bot, message.chat.id, "Unauthorized.")
          end

        when "report", "/report"
          Bot::Messaging.send_message(bot, message.chat.id, "Generating report...")
          unless Bot::CSVStore.subscribed?(message.from.id)
            Bot::Messaging.send_message(bot, message.chat.id, "Please subscribe first: `w <city>`", parse_mode: "Markdown")
            next
          end
          report = Bot::Report.build_fresh_report_for(message.from.id)
          Bot::Messaging.send_message(bot, message.chat.id, report, parse_mode: "HTML")

        when "buses", "/buses", "transport", "/transport"
          Bot::Transport.start_bus_flow(bot, message.chat.id)

        when "music", "/music"
          Bot::Messaging.send_message(bot, message.chat.id, "Loading link...")
          unless Bot::CSVStore.subscribed?(message.from.id)
            Bot::Messaging.send_message(bot, message.chat.id, "Please subscribe first: `w <city>`", parse_mode: "Markdown")
            next
          end
          Bot::MusicHelpers.send_music_links(bot, message.chat.id, limit: nil)

        when "broadcast 4 all", "/broadcast"
          if ADMIN_ID.include?(message.from.id.to_s)
            Bot::Messaging.send_message(bot, message.chat.id, "Broadcasting...")
            Bot::Broadcast.broadcast_daily_reports(bot)
          else
            Bot::Messaging.send_message(bot, message.chat.id, "Unauthorized.")
          end

        else
          Bot::Messaging.send_message(bot, message.chat.id, "Type start")
        end
      rescue Faraday::SSLError, OpenSSL::SSL::SSLError => e
        warn "[listen] SSL error: #{e.class} - #{e.message}"
        sleep 5 # avoid tight retry loop
        retry
      rescue => e
        warn "[listen] General error: #{e.class} - #{e.message}"
        sleep 5
        retry
      end
    end

  end
end

main if __FILE__ == $0
