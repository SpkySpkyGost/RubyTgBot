# frozen_string_literal: true
# encoding: UTF-8

require "playwright"
require "nokogiri"
require "json"
require "fileutils"
require_relative "../config"

module SpotifyPlaylist
  module_function

  PLAYLIST_URL  = Config::SPOTIFY_MY_PLAYLIST_URL
  OUT_FILE      = Config::SPOTIFY_FILE

  # Optional: allow overriding CLI path via ENV
  PLAYWRIGHT_CLI = ENV["PLAYWRIGHT_CLI"] ||
                   File.expand_path(File.join(Dir.pwd, "node_modules", ".bin",
                                              Gem.win_platform? ? "playwright.cmd" : "playwright"))

  def ensure_cli!
    raise "Playwright CLI not found at #{PLAYWRIGHT_CLI}. Run `npm i -D playwright && npx playwright install chromium`" unless File.exist?(PLAYWRIGHT_CLI)
  end

  def fetch_and_save(out: OUT_FILE, playlist_url: PLAYLIST_URL)
    ensure_cli!

    tracks = []

    Playwright.create(playwright_cli_executable_path: PLAYWRIGHT_CLI) do |pw|
      pw.chromium.launch(headless: true) do |browser|
        context = browser.new_context
        page = context.new_page

        page.goto(playlist_url)

        # Cookie banner (best‑effort)
        begin
          page.click("button:has-text('Accept all'), button:has-text('Accept All'), button:has-text('Accept cookies')", timeout: 3000)
        rescue Playwright::TimeoutError
        end

        # Wait for first rows
        page.wait_for_selector("[data-testid='tracklist-row']", timeout: 15_000)

        # Scroll-until-stable loop to load ALL rows
        rows = page.locator("[data-testid='tracklist-row']")
        prev = 0
        idle_rounds = 0
        max_idle = 4
        rounds = 0
        max_rounds = 400

        while idle_rounds < max_idle && rounds < max_rounds
          count = rows.count
          if count > prev
            prev = count
            idle_rounds = 0
          else
            idle_rounds += 1
          end

          # nudge the list
          begin
            rows.nth([count - 1, 0].max).scroll_into_view_if_needed
          rescue StandardError
          end
          begin
            page.keyboard.press("End")
          rescue StandardError
          end
          page.mouse.wheel(0, 2800) rescue nil
          page.wait_for_timeout(350)
          rounds += 1
        end

        # Parse rendered HTML
        html = page.content
        doc  = Nokogiri::HTML(html)

        seen = {}
        doc.css("[data-testid='tracklist-row']").each do |row|
          title  = row.at_css("[data-testid='internal-track-link'] div")&.text&.strip
          artist = row.at_css("a[href^='/artist/']")&.text&.strip
          href   = row.at_css("[data-testid='internal-track-link']")&.[]("href")
          url    = href ? "https://open.spotify.com#{href}" : nil
          dur    = row.at_css("div[aria-colindex='5'] .encore-text-body-small")&.text&.strip
          next if title.to_s.empty?

          key = url || "#{title}|#{artist}"
          next if seen[key]
          seen[key] = true

          tracks << {
            "name" => title,
            "artists" => [{ "name" => artist }],
            "external_urls" => { "spotify" => url },
            "duration" => dur
          }
        end
      end
    end

    FileUtils.mkdir_p(File.dirname(out))
    File.write(out, JSON.pretty_generate({ "items" => tracks }), mode: "w:UTF-8")
    puts "[spotify_playlist] Saved #{tracks.size} tracks to #{out}"
    out
  rescue => e
    warn "[spotify_playlist] #{e.class}: #{e.message}"
    # still ensure file exists with empty schema
    FileUtils.mkdir_p(File.dirname(out))
    File.write(out, JSON.pretty_generate({ "items" => [] }), mode: "w:UTF-8") unless File.exist?(out)
    out
  end
end
