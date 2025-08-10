# frozen_string_literal: true

module Bot
  module Messaging
    extend self

    @last_bot_msg = {}
    @rec_msgs     = Hash.new { |h, k| h[k] = [] }
    @bus_msgs     = Hash.new { |h, k| h[k] = [] }

    def delete_previous_message(bot, chat_id)
      key = Util.chid(chat_id)
      if @last_bot_msg[key]
        begin
          bot.api.delete_message(chat_id: chat_id, message_id: @last_bot_msg[key])
        rescue Telegram::Bot::Exceptions::ResponseError
          # Ignore if already deleted or too old
        end
      end
    end

    # bucket: :rec or :bus for tracking
    def send_message(bot, chat_id, text, track: false, bucket: :rec, suppress_delete: false, **kwargs)
      delete_previous_message(bot, chat_id) unless suppress_delete
      msg = bot.api.send_message(
        chat_id: chat_id,
        text:    text,
        reply_markup: (::KEYBOARD rescue nil),
        **kwargs
      )
      key = Util.chid(chat_id)
      @last_bot_msg[key] = msg.message_id unless suppress_delete
      if track
        case bucket
        when :rec then @rec_msgs[key] << msg.message_id
        when :bus then @bus_msgs[key] << msg.message_id
        end
      end
      msg
    end

    def with_chunks(lines, chat_id:, bot:)
      text = lines.join("\n")
      if text.size <= TELEGRAM_MAX_CHARS
        send_message(bot, chat_id, text)
        return
      end
      chunk = +""
      lines.each do |line|
        if chunk.size + line.size + 1 > TELEGRAM_MAX_CHARS
          send_message(bot, chat_id, chunk)
          chunk = +""
        end
        chunk << (chunk.empty? ? line : "\n#{line}")
      end
      send_message(bot, chat_id, chunk) unless chunk.empty?
    end

    # ——— Recommender clear button + clear ———
    def send_recommender_clear_button(bot, chat_id)
      kb = Telegram::Bot::Types::InlineKeyboardMarkup.new(
        inline_keyboard: [
          [Telegram::Bot::Types::InlineKeyboardButton.new(text: "🧹 Clear recommender messages", callback_data: "rec_clear")]
        ]
      )
      send_message(
        bot, chat_id,
        "Recommender tests finished. You can clear them below.",
        suppress_delete: true, reply_markup: kb, track: true, bucket: :rec
      )
    end

    def clear_recommender_messages(bot, chat_id)
      key = Util.chid(chat_id)
      ids = @rec_msgs[key]
      return if ids.empty?
      ids.each do |mid|
        begin
          bot.api.delete_message(chat_id: chat_id, message_id: mid)
        rescue Telegram::Bot::Exceptions::ResponseError
        end
      end
      @rec_msgs[key].clear
    end

    # Expose for other modules
    def bus_msgs; @bus_msgs; end
  end
end
