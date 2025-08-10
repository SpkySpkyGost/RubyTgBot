# frozen_string_literal: true

require "nokogiri"
require "uri"
require "cgi"
require "net/http"

module IdosParser
  BASE_URL = "https://idos.cz/vlakyautobusymhdvse/spojeni/vysledky/"

  module_function

  # ---------- existing parse_and_build + helpers (unchanged) ----------
  def parse_and_build(html:, query_url: nil)
    doc = Nokogiri::HTML(html)
    from = extract_from(doc)
    to   = extract_to(doc)
    date, time = extract_date_time(query_url: query_url, doc: doc)

    query_params = {}
    query_params[:date] = date if date
    query_params[:time] = time if time
    query_params[:f]    = from if from
    query_params[:t]    = to   if to
    q = URI.encode_www_form(query_params)

    {
      base_url: BASE_URL,
      date: date,
      time: time,
      from: from,
      to:   to,
      full_url: q.empty? ? BASE_URL : "#{BASE_URL}?#{q}"
    }
  end

  def extract_from(doc)
    node = doc.at_css(".connection-details .line-item .outside-of-popup:first-of-type ul.stations.first li.item:first-of-type strong.name")
    clean_stop(node&.text&.strip)
  end

  def extract_to(doc)
    last_leg = doc.at_css(".connection-details .line-item .outside-of-popup:last-of-type")
    node = last_leg&.at_css("ul.stations.last li.item.last strong.name") ||
           last_leg&.css("ul.stations.last strong.name")&.last
    clean_stop(node&.text&.strip)
  end

  def extract_date_time(query_url:, doc:)
    if query_url && !query_url.empty?
      u = URI(query_url)
      params = CGI.parse(u.query.to_s)
      raw_date = params["date"]&.first&.strip
      raw_time = params["time"]&.first&.strip
      date = normalize_date(raw_date)
      time = normalize_time(raw_time)
      return [date, time] if date || time
    end

    if (match = doc.to_html.match(/(\d{2}\.\d{2}\.\d{4})\s+(\d{2}:\d{2})/))
      date = normalize_date(match[1])
      time = normalize_time(match[2])
      return [date, time] if date || time
    end

    [nil, nil]
  end

  def normalize_date(s) = s =~ /^\d{2}\.\d{2}\.\d{4}$/ ? s : nil
  def normalize_time(s) = s =~ /^\d{2}:\d{2}$/ ? s : nil

  def clean_stop(name)
    return nil if name.nil? || name.empty?
    name.include?(",,") ? name.split(",,", 2).last.strip : name
  end

  # ---------- NEW: connections parser ----------
  def parse_connections(html, limit: 3)
    doc = Nokogiri::HTML(html)
    boxes = doc.css('div.connection-list > div[id^="connectionBox-"]').first(limit) || []
    boxes.map { |box| parse_box(box) }
  end

  def parse_box(box)
    head = box.at_css('.connection-head')

    # Time is text node before <span class="date-after">
    time_text = begin
                  h2 = head.at_css('h2.date')
                  h2 ? h2.children.find { |n| n.text? }&.text&.strip : nil
                end

    date_after = head.at_css('h2.date .date-after')&.text&.strip
    total      = head.at_css('p.total strong')&.text&.strip

    price_text = box.at_css('.connection-expand .price-value')&.text
    price_kc   = price_text ? price_text.gsub(/[^\d]/, '').to_i : nil
    price_kc   = nil if price_kc == 0

    legs = []
    box.css('.connection-details .outside-of-popup').each do |leg|
      line  = leg.at_css('.line-title .title-container h3 span')&.text&.strip
      owner = leg.at_css('.line-right-part .owner span')&.text&.strip
      specs = leg.at_css('.line-title .specs')&.text&.gsub(/\s+/, ' ')&.strip

      # optional walk segment inside same block
      walk_note = leg.at_css('.walk')&.text&.gsub(/\s+/, ' ')&.strip

      dep_li = leg.at_css('ul.stations:first-of-type li.item:first-of-type') ||
               leg.at_css('ul.stations li.item:first-of-type')
      arr_li = leg.at_css('ul.stations:last-of-type li.item.last') ||
               leg.css('ul.stations li.item').last

      dep_time = dep_li&.at_css('p.time')&.text&.strip
      dep_stop = clean_stop(dep_li&.at_css('strong.name')&.text&.strip)
      arr_time = arr_li&.at_css('p.time')&.text&.strip
      arr_stop = clean_stop(arr_li&.at_css('strong.name')&.text&.strip)

      legs << {
        line: line,
        operator: owner,
        specs: specs,
        dep_time: dep_time,
        dep_stop: dep_stop,
        arr_time: arr_time,
        arr_stop: arr_stop
      }

      legs << { line: "WALK", note: walk_note } if walk_note && !walk_note.empty?
    end

    {
      id: box["id"],
      depart_time: time_text,
      date_label: date_after,    # e.g. "11.8. po"
      total: total,              # e.g. "1 hod 23 min"
      price_kc: price_kc,        # integer or nil
      legs: legs
    }
  end
end

# ---------------------
# Main test harness
# ---------------------
if __FILE__ == $0
  test_url = "https://idos.cz/vlakyautobusymhdvse/spojeni/vysledky/?date=11.08.2025&time=01:00&f=%C5%A0aldovo%20n%C3%A1m%C4%9Bst%C3%AD&fc=337003&t=%C4%8Cern%C3%BD%20Most&tc=301003"

  puts "[TEST] Fetching: #{test_url}"
  uri  = URI(test_url)
  html = Net::HTTP.get(uri)

  header = IdosParser.parse_and_build(html: html, query_url: test_url)
  puts "--- Header ---"
  puts "From: #{header[:from]} -> To: #{header[:to]} | Date: #{header[:date]} Time: #{header[:time]}"
  puts "URL:  #{header[:full_url]}"

  puts "\n--- First 3 connections ---"
  conns = IdosParser.parse_connections(html, limit: 3)
  conns.each_with_index do |c, i|
    puts "\n## Connection #{i+1} (#{c[:depart_time]} • #{c[:date_label]} • total #{c[:total]}#{c[:price_kc] ? " • ~#{c[:price_kc]} Kč" : ""})"
    c[:legs].each do |leg|
      if leg[:line] == "WALK"
        puts "   - WALK: #{leg[:note]}"
      else
        puts "   - #{leg[:line]} (#{leg[:operator]}) #{leg[:dep_time]} #{leg[:dep_stop]} → #{leg[:arr_time]} #{leg[:arr_stop]} #{leg[:specs] && !leg[:specs].empty? ? "[#{leg[:specs]}]" : ""}"
      end
    end
  end
end
