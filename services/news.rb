# frozen_string_literal: true

# news.rb
# Minimal scraper for your page structure: picks <div class="font-semibold text-3xl"><a ...>
# Saves a dictionary: { "Article1" => { "name" => ..., "link" => ... }, ... }

require 'json'
require 'uri'
require 'net/http'
require 'nokogiri'
require 'cgi'

module News
  module_function

  # Always return UTF-8 text
  def http_get_utf8(url)
    uri = URI(url)
    res = Net::HTTP.start(uri.host, uri.port, use_ssl: (uri.scheme == 'https')) do |http|
      req = Net::HTTP::Get.new(uri)
      req['User-Agent'] = 'RubyNewsScraper/1.0'
      req['Accept']     = 'text/html,application/xhtml+xml'
      http.request(req)
    end
    raise "HTTP #{res.code} #{res.message}" unless res.is_a?(Net::HTTPSuccess)

    body = res.body # ASCII-8BIT

    # Prefer UTF-8 if bytes are already valid UTF-8
    try = body.dup
    try.force_encoding('UTF-8')
    return try if try.valid_encoding?

    # Else detect charset from header or meta
    header_cs = charset_from_content_type(res['content-type'])
    meta_cs   = detect_html_meta_charset(body)

    cs = header_cs || meta_cs
    if cs
      begin
        return body.force_encoding(cs).encode('UTF-8', invalid: :replace, undef: :replace)
      rescue Encoding::InvalidByteSequenceError, Encoding::UndefinedConversionError
        # fall through
      end
    end

    # Fallback: replace invalid bytes
    body.force_encoding('BINARY').encode('UTF-8', invalid: :replace, undef: :replace)
  end

  def charset_from_content_type(ct)
    return nil unless ct
    m = ct.match(/charset=([A-Za-z0-9_\-]+)/i)
    m && m[1]
  end

  def detect_html_meta_charset(bytes)
    head = bytes[0, 4000].to_s
    if (m = head.match(/<meta[^>]*charset=["']?([A-Za-z0-9_\-]+)["']?/i))
      return m[1]
    end
    if (m = head.match(/<meta[^>]*http-equiv=["']content-type["'][^>]*content=["'][^"']*charset=([A-Za-z0-9_\-]+)/i))
      return m[1]
    end
    nil
  end

  def fetch_and_save(count: Config::NEWS_COUNT)
    dict = fetch_as_dictionary(
      base_url:  Config::BASE_NEWS_URL,
      page_url:  Config::NEWS_PAGE_URL,
      max_items: count
    )
    File.write(Config::NEWS_FILE, JSON.pretty_generate(dict))
    dict
  rescue => e
    warn "[News] fetch_and_save error: #{e.class}: #{e.message}"
    nil
  end

  # Build `{"Article1"=>{name,link}, ...}`
  def fetch_as_dictionary(base_url:, page_url:, max_items: 3)
    html = http_get_utf8(page_url)
    doc  = Nokogiri::HTML(html)

    links = doc.css('div.font-semibold.text-3xl a')
    items = {}
    links.first(max_items).each_with_index do |a, idx|
      name = a.text.to_s.strip
      href = a['href'].to_s
      next if name.empty? || href.empty?

      link_abs = absolutize(base_url, href)
      items["Article#{idx + 1}"] = { "name" => name, "link" => link_abs }
    end

    items
  end

  def read_saved
    return {} unless File.exist?(Config::NEWS_FILE)
    JSON.parse(File.read(Config::NEWS_FILE, encoding: 'UTF-8'))
  rescue => e
    warn "[News] read_saved error: #{e.class}: #{e.message}"
    {}
  end

  # Lines suitable for Telegram message
  # e.g. ["1. Title — https://...", "2. Title — https://..."]
  def summary_lines(limit: Config::NEWS_COUNT)
    saved = read_saved
    keys  = saved.keys.sort_by { |k| k[/\d+/].to_i }
    keys.first(limit).map.with_index(1) do |k, i|
      name = saved[k]["name"]
      link = saved[k]["link"]
      "#{i}. #{name} — #{link}"
    end
  end

  def absolutize(base_url, href)
    u = URI(href)
    u = URI.join(base_url, href) if u.relative?
    u.to_s
  end
end
