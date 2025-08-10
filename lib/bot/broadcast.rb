# frozen_string_literal: true

module Bot
  module Broadcast
    extend self

    def broadcast_daily_reports(bot)
      SpotifyPlaylist.fetch_and_save(out: SPOTIFY_FILE, playlist_url: Config::SPOTIFY_MY_PLAYLIST_URL)
      Music.fetch_recommendations
      News.fetch_and_save(count: Config::NEWS_COUNT)

      rows = Bot::CSVStore.all_user_rows
      return if rows.empty?

      rows.each do |row|
        user_id = row["user_id"].to_s.strip
        next if user_id.empty?

        chat_id = user_id
        city    = (row["city"] || "").strip

        if city.empty?
          begin
            Bot::Messaging.send_message(
              bot, chat_id,
              "Hi! I’d love to send you a daily report, but I don’t have your city yet.\n" \
                "Please send: `w <city>`",
              parse_mode: "Markdown"
            )
          rescue => e
            warn "[broadcast] unable to nudge #{user_id}: #{e.class}: #{e.message}"
          end
          next
        end

        begin
          report = Bot::Report.build_fresh_report_for(user_id)
          Bot::Messaging.send_message(bot, chat_id, report, parse_mode: "HTML")
          sleep 0.5
        rescue => e
          warn "[broadcast] failed for user #{user_id}: #{e.class}: #{e.message}"
        end
      end
    end
  end
end
