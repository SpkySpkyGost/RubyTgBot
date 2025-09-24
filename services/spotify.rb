# frozen_string_literal: true
# encoding: UTF-8

require "playwright"
require "nokogiri"
require "json"
require "fileutils"
require "set"
require_relative "../config"

module SpotifyPlaylist
  module_function

  PLAYLIST_URL  = Config::SPOTIFY_MY_PLAYLIST_URL
  OUT_FILE      = Config::SPOTIFY_FILE

  PLAYWRIGHT_CLI = ENV["PLAYWRIGHT_CLI"] ||
                   File.expand_path(File.join(Dir.pwd, "node_modules", ".bin",
                                              Gem.win_platform? ? "playwright.cmd" : "playwright"))

  def ensure_cli!
    raise "Playwright CLI not found at #{PLAYWRIGHT_CLI}. Run `npm i -D playwright && npx playwright install chromium`" unless File.exist?(PLAYWRIGHT_CLI)
  end

  def scroll_and_collect_track_rows(page, max_idle: 10, max_rounds: 100)
    puts "[scrolling] Starting scroll + capture of tracklist-row HTML..."
    rows = page.locator("[data-testid='tracklist-row']")
    prev_count = 0
    idle_rounds = 0
    round = 0

    html_snippets = Set.new

    while round < max_rounds && idle_rounds < max_idle
      count = rows.count
      puts "[scrolling] round: #{round}, visible rows: #{count}"

      # Сохраняем текущие видимые элементы (outerHTML всех строк)
      rows.evaluate_all("nodes => nodes.map(n => n.outerHTML)").each do |html|
        html_snippets << html
      end

      if count > prev_count
        prev_count = count
        idle_rounds = 0
      else
        idle_rounds += 1
      end

      rows.nth([count - 1, 0].max).scroll_into_view_if_needed rescue nil
      page.keyboard.press("PageDown") rescue nil
      page.mouse.wheel(0, 1500) rescue nil
      page.wait_for_timeout(600)

      round += 1
    end

    puts "[scrolling] Done. Collected #{html_snippets.size} unique row snippets."
    html_snippets
  end

  def fetch_and_save(out: OUT_FILE, playlist_url: PLAYLIST_URL)
    ensure_cli!

    tracks = []

    Playwright.create(playwright_cli_executable_path: PLAYWRIGHT_CLI) do |pw|
      pw.chromium.launch(headless: false) do |browser|
        context = browser.new_context
        page = context.new_page

        page.goto(playlist_url)
        page.wait_for_timeout(2000) # дать JS загрузиться

        # Попытка закрыть cookie
        begin
          page.click("button:has-text('Accept all'), button:has-text('Accept All'), button:has-text('Accept cookies')", timeout: 3000)
        rescue Playwright::TimeoutError
        end

        page.wait_for_selector("[data-testid='tracklist-row']", timeout: 10_000)
        puts "[debug] Tracklist rows ready"

        html_rows = scroll_and_collect_track_rows(page)

        seen = {}
        fragment = Nokogiri::HTML.fragment(html_rows.to_a.join)

        rows = fragment.css('[data-testid="tracklist-row"]')
        puts "[debug] Parsing #{rows.size} collected rows..."

        rows.each do |row|
          title  = row.at_css("[data-testid='internal-track-link'] div")&.text&.strip
          artist = row.at_css("a[href^='/artist/']")&.text&.strip
          href   = row.at_css("[data-testid='internal-track-link']")&.[]("href")
          url    = href ? "https://open.spotify.com#{href}" : nil
          dur    = row.at_css("div[aria-colindex='5'] .encore-text-body-small")&.text&.strip

          if dur.nil?
            puts "[debug] Skipping row without duration (likely recommendation)"
            next
          end

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
    FileUtils.mkdir_p(File.dirname(out))
    File.write(out, JSON.pretty_generate({ "items" => [] }), mode: "w:UTF-8") unless File.exist?(out)
    out
  end
end
