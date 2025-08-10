# frozen_string_literal: true
require "json"
require "net/http"
require "uri"
require "fileutils"
require_relative "../config"

module Music
  FILEPATH         = Config::MUSIC_FILE
  DEFAULT_SKELETON = { "content" => [] }.freeze
  API_BASE         = Config::API_side_link_music
  SEEDS =Config::MUSIC_SEEDS
  def self.ensure_file!(path = FILEPATH)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, JSON.pretty_generate(DEFAULT_SKELETON)) unless File.exist?(path)
  end

  def self.save_to_file(data, filename = FILEPATH)
    FileUtils.mkdir_p(File.dirname(filename))
    File.write(filename, JSON.pretty_generate(data))
    puts "[music] Saved data to #{filename}"
    filename
  end

  def self.extract_tracks(json_data)
    (json_data["content"] || []).map { |t| [t["trackTitle"], t["href"]] }
  end

  def self.get_recommendations(seeds:SEEDS, size: 15, negative_seeds: [], features: {})
    extract = ->(s) { s[%r{track/([A-Za-z0-9]+)}, 1] || s.to_s.strip }
    seed_ids = seeds.map(&extract)
    neg_ids  = negative_seeds.map(&extract)

    params = [["size", size]]
    seed_ids.each { |id| params << ["seeds", id] }
    neg_ids.each  { |id| params << ["negativeSeeds", id] }

    (Config::MUSIC_DEFAULT_FEATURES.merge(features || {})).each do |k, v|
      params << [k, v]
    end

    uri = URI(API_BASE)
    uri.query = URI.encode_www_form(params)

    resp = Net::HTTP.get_response(uri)
    raise "API request failed with #{resp.code}: #{resp.body}" unless resp.code == "200"
    JSON.parse(resp.body)
  end

  def self.fetch_recommendations(track_ids: nil, size: 15, negative_seeds: [], features: {})
    seeds = (track_ids || Config::MUSIC_SEEDS).uniq.first(10)
    ensure_file!(FILEPATH)

    data = get_recommendations(
      seeds: seeds.first(5),
      size: size,
      negative_seeds: negative_seeds,
      features: features
    )

    save_to_file(data, FILEPATH)
    lines = extract_tracks(data).map { |title, link| "#{title} - #{link}" }
    "Saved #{lines.size} tracks to #{FILEPATH}\n#{lines.first(5).join("\n")}"
  end
end
