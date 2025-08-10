# frozen_string_literal: true

module Bot
  module Rec
    extend self

    def format_recs(result, limit: 5)
      return result if result.is_a?(String)

      items =
        if result.is_a?(Array)
          result
        elsif result.is_a?(Hash) && result["items"].is_a?(Array)
          result["items"]
        elsif result.is_a?(Hash) && result["recommendations"].is_a?(Array)
          result["recommendations"]
        else
          return "Unknown response shape:\n```json\n#{JSON.pretty_generate(result)[0, 1500]}\n```"
        end

      lines = items.first(limit).map.with_index(1) do |it, i|
        code = it["code"] || it["product_code"] || it["id"] || "?"
        name = it["name"] || it["title"] || it["product_name"] || "?"
        "#{i}. #{name} (#{code})"
      end

      lines.empty? ? "No items returned." : lines.join("\n")
    end

    def send_health_then_request(bot, chat_id, title:, url:)
      health = Bot::HTTP.get_health
      Bot::Messaging.send_message(
        bot, chat_id,
        "🔎 *#{title}* — Health:\n```\n#{health}\n```",
        parse_mode: "Markdown",
        suppress_delete: true, track: true, bucket: :rec
      )

      result  = Bot::HTTP.get_json_or_text(url)
      summary = format_recs(result, limit: 5)
      Bot::Messaging.send_message(
        bot, chat_id,
        "🔧 *#{title}*\n`#{url}`\n\n#{summary}",
        parse_mode: "Markdown",
        suppress_delete: true, track: true, bucket: :rec
      )
    end

    def run_recommender_for(bot, chat_id, user_id)
      test_user_id = user_id.to_s

      scenarios = [
        { title: "Baseline",                               params: {} },
        { title: "Specified amount (3)",                   params: { recs_amount: 3 } },
        { title: "Filter already liked (true)",            params: { filter_already_liked_items: true } },
        { title: "Randomness (random_multiplier=1)",       params: { random_multiplier: 1 } },
        { title: "Combo: amount=3 + filter=true + random=2",
          params: { recs_amount: 3, filter_already_liked_items: true, random_multiplier: 2 } }
      ]

      scenarios.each do |sc|
        url = Bot::HTTP.build_recommend_url(test_user_id, sc[:params])
        send_health_then_request(bot, chat_id, title: sc[:title], url: url)
        sleep 0.6
      end

      Bot::Messaging.send_recommender_clear_button(bot, chat_id)
    rescue => e
      warn "[recommender] failed for user #{user_id}: #{e.class}: #{e.message}"
    end
  end
end
