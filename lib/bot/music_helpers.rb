# frozen_string_literal: true
require "json"

module Bot
  module MusicHelpers
    extend self

    def random_music_song
      data = JSON.parse(File.read(MUSIC_FILE))
      tracks = (data["content"] || [])
      return "No music data" if tracks.empty?
      t = tracks.sample
      "#{t['trackTitle']} — #{(t['artists'] || []).map { |a| a['name'] }.join(', ')} — #{t['href']}"
    end

    def random_spotify_song
      data = JSON.parse(File.read(SPOTIFY_FILE))
      items = (data["items"] || [])
      return "No Spotify data" if items.empty?
      t = items.sample
      "#{t['name']} — #{(t['artists'] || []).map { |a| a['name'] }.join(', ')} — #{t.dig('external_urls', 'spotify')}"
    end

    def collect_music_links
      links = []

      begin
        data = JSON.parse(File.read(MUSIC_FILE))
        links += (data["content"] || []).map { |t| t["href"] }.compact
      rescue => e
        warn "[music-links] MUSIC_FILE read error: #{e.class}: #{e.message}"
      end

      begin
        data = JSON.parse(File.read(SPOTIFY_FILE))
        links += (data["items"] || []).map { |it| it.dig("external_urls", "spotify") }.compact
      rescue => e
        warn "[music-links] SPOTIFY_FILE read error: #{e.class}: #{e.message}"
      end

      links.uniq
    end

    def send_music_links(bot, chat_id, limit: nil)
      links = collect_music_links
      links = links.first(limit) if limit

      safe_limit = 3900
      chunk = +""

      send_chunk = lambda do
        return if chunk.empty?
        Messaging.send_message(
          bot, chat_id, chunk,
          disable_web_page_preview: true
        )
        chunk.clear
      end

      links.each do |ln|
        line = ln.to_s.strip
        next if line.empty?
        if chunk.empty?
          chunk << line
        elsif (chunk.size + 1 + line.size) > safe_limit
          send_chunk.call
          chunk << line
        else
          chunk << "\n" << line
        end
      end
      send_chunk.call
    end

    def format_music_lines
      data = JSON.parse(File.read(MUSIC_FILE))
      (data["content"] || []).map do |t|
        title   = t["trackTitle"]
        artists = (t["artists"] || []).map { |a| a["name"] }.join(", ")
        link    = t["href"]
        "#{title} — #{artists} — #{link}"
      end
    end

    def format_spotify_lines
      data = JSON.parse(File.read(SPOTIFY_FILE))
      (data["items"] || []).map do |item|
        title   = item["name"]
        artists = (item["artists"] || []).map { |a| a["name"] }.join(", ")
        link    = item.dig("external_urls", "spotify")
        "#{title} — #{artists} — #{link}"
      end
    end
  end
end
