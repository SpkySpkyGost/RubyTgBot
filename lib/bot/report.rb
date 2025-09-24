# frozen_string_literal: true

module Bot
  module Report
    extend self

    def build_fresh_report_for(user_id)
      city = CSVStore.get_user_city(user_id)
      return "Hey! Before I can make your report, please tell me your city: send `w <city>`" if city.nil? || city.empty?

      place = Weather.geocode(city)
      return "Hmm… I couldn't find that city. Could you double-check the spelling?" if place.nil?

      cur = Weather.forecast(place[:lat], place[:lon])
      return "Oops! The weather service isn’t responding right now." if cur.nil?

      weather_data = Weather.format_weather(place, cur)

      music_line = begin
                     MusicHelpers.random_music_song
                   rescue => e
                     "No music data (#{e.class})"
                   end

      spotify_line = begin
                       MusicHelpers.random_spotify_song
                     rescue => e
                       "No Spotify data (#{e.class})"
                     end
      extra_spotify_line = begin
                             MusicHelpers.random_spotify_song
                           rescue => e
                             "No Spotify data (#{e.class})"
                           end

      news_lines = begin
                     News.summary_lines(limit: Config::NEWS_COUNT)
                   rescue => e
                     warn "[news] #{e.class}: #{e.message}"
                     []
                   end

      news_block =
        if news_lines.empty?
          "_No news available right now._"
        else
          news_lines.map { |line|
            if line =~ /^\s*\d+\.\s*(.+?)\s+—\s+(https?:\/\/\S+)/
              title = Util.html_escape($1)
              url   = Util.html_escape($2)
              "• <a href=\"#{url}\">#{title}</a>"
            else
              Util.html_escape(line)
            end
          }.join("\n")
        end

      body =
        "<b>🌍 Daily Report for you:</b>\n\n" \
          "<b>☀️ Weather update:</b>\n" \
          "#{Util.html_escape(weather_data)}\n\n" \
          "<b>🗞️ Top news:</b>\n" \
          "#{news_block}\n\n" \
          "<b>🎵 Today’s music picks:</b>\n" \
          "From our music list: <i>#{Util.html_escape(music_line)}</i>\n" \
          "From Spotify playlist: <i>#{Util.html_escape(spotify_line)}</i>\n\n" \
          "Another Spotify pick: <i>#{Util.html_escape(extra_spotify_line)}</i>\n\n" \
          "Stay strong 💪"

      body
    end
  end
end
