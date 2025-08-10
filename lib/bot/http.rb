# frozen_string_literal: true
require "net/http"
require "uri"
require "json"

module Bot
  module HTTP
    module_function

    def build_recommend_url(user_id, params = {})
      q = { user_id: user_id }.merge(params)
      "#{BASE_REC_URL}/recommend?#{URI.encode_www_form(q)}"
    end

    def get_health
      Net::HTTP.get(URI("#{BASE_REC_URL}/health"))
    rescue => e
      "ERROR: #{e.class}: #{e.message}"
    end

    def get_json_or_text(url)
      res = Net::HTTP.get_response(URI(url))
      return "HTTP #{res.code} #{res.message}" unless res.is_a?(Net::HTTPSuccess)
      body = res.body
      JSON.parse(body)
    rescue JSON::ParserError
      body # not JSON, return raw
    rescue => e
      "ERROR: #{e.class}: #{e.message}"
    end

    # Helper to GET and parse JSON
    def fetch_json(url)
      uri = URI(url)
      res = Net::HTTP.get_response(uri)
      return nil unless res.is_a?(Net::HTTPSuccess)
      JSON.parse(res.body)
    rescue => e
      warn "[HTTP error] #{e.class}: #{e.message}"
      nil
    end
  end
end
