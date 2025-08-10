# frozen_string_literal: true
require "uri"
require "net/http"

module Bot
  module Transport
    extend self

    BUS_FLOW = Hash.new { |h, k| h[k] = { step: :idle, data: {} } }

    def reset_bus_flow(chat_id)
      BUS_FLOW[chat_id][:step] = :idle
      BUS_FLOW[chat_id][:data] = {}
    end

    def start_bus_flow(chat_id)
      BUS_FLOW[chat_id][:step] = :ground_zero
      BUS_FLOW[chat_id][:data] = {}
    end

    def handle_bus_flow_input(bot, message)
      chat_id = message.chat.id
      state   = BUS_FLOW[chat_id]
      text    = (message.text || "").strip

      case state[:step]
      when :ground_zero
        Messaging.send_message(bot, chat_id, "Running transport search script...", track: true, bucket: :bus)
        state[:step] = :ask_from
        Messaging.send_message(bot, chat_id, "From where? (start stop)", track: true, bucket: :bus)
        return true

      when :ask_from
        state[:data][:from] = text
        state[:step] = :ask_to
        Bot::Messaging.send_message(bot, chat_id, "To where? (destination stop)", track: true, bucket: :bus)
        return true

      when :ask_to
        state[:data][:to] = text
        state[:step] = :ask_date
        Bot::Messaging.send_message(bot, chat_id, "Date? (DD.MM.YYYY) — or send `today` / leave blank", track: true, bucket: :bus)
        return true

      when :ask_date
        date = text.empty? || text.downcase == "today" ? nil : text
        unless date.nil? || date =~ /^\d{2}\.\d{2}\.\d{4}$/
          Bot::Messaging.send_message(bot, chat_id, "Use DD.MM.YYYY (e.g. 11.08.2025) or `today`.", track: true, bucket: :bus)
          return true
        end
        state[:data][:date] = date
        state[:step] = :ask_time
        Bot::Messaging.send_message(bot, chat_id, "Time? (HH:MM) — or send `now` / leave blank", track: true, bucket: :bus)
        return true

      when :ask_time
        time = text.empty? || text.downcase == "now" ? nil : text
        unless time.nil? || time =~ /^\d{2}:\d{2}$/
          Bot::Messaging.send_message(bot, chat_id, "Use HH:MM (e.g. 05:10) or `now`.", track: true, bucket: :bus)
          return true
        end
        state[:data][:time] = time

        from = state[:data][:from]
        to   = state[:data][:to]
        date = state[:data][:date] # can be nil
        time = state[:data][:time] # can be nil

        base_url = "https://idos.cz/vlakyautobusymhdvse/spojeni/vysledky/"
        q = {}
        q[:date] = date if date
        q[:time] = time if time
        q[:f]    = from
        q[:t]    = to
        full_url = q.empty? ? base_url : "#{base_url}?#{URI.encode_www_form(q)}"

        Bot::Messaging.send_message(bot, chat_id, full_url, disable_web_page_preview: true, track: true, bucket: :bus)

        begin
          html  = Net::HTTP.get(URI(full_url))
          conns = IdosParser.parse_connections(html, limit: 3)

          if conns.nil? || conns.empty?
            Bot::Messaging.send_message(bot, chat_id, "No connections found 🤷‍♂️", track: true, bucket: :bus)
          else
            lines = []
            conns.each_with_index do |c, i|
              header = "##{i+1} • #{c[:depart_time]} • #{c[:date_label]} • #{c[:total]}"
              header += " • ~#{c[:price_kc]} Kč" if c[:price_kc]
              lines << header

              c[:legs].each do |leg|
                if leg[:line] == "WALK"
                  lines << "   · WALK: #{leg[:note]}"
                else
                  spec = (leg[:specs] && !leg[:specs].empty?) ? " [#{leg[:specs]}]" : ""
                  oper = leg[:operator] ? " (#{leg[:operator]})" : ""
                  lines << "   · #{leg[:line]}#{oper} — #{leg[:dep_time]} #{leg[:dep_stop]} → #{leg[:arr_time]} #{leg[:arr_stop]}#{spec}"
                end
              end
            end

            msg = lines.join("\n")
            msg.scan(/.{1,#{TELEGRAM_MAX_CHARS}}(?:\n|\z)/m).each do |chunk|
              Bot::Messaging.send_message(bot, chat_id, chunk, track: true, bucket: :bus)
            end
          end
        rescue => e
          warn "[transport] parse error: #{e.class}: #{e.message}"
          Bot::Messaging.send_message(bot, chat_id, "Sorry, failed to parse results (#{e.class}).", track: true, bucket: :bus)
        end

        send_transport_clear_button(bot, chat_id)
        reset_bus_flow(chat_id)
        return true

      else
        false
      end
    end

    # NEW: add missing UI + clear handlers used by callbacks
    def send_transport_clear_button(bot, chat_id)
      kb = Telegram::Bot::Types::InlineKeyboardMarkup.new(
        inline_keyboard: [
          [Telegram::Bot::Types::InlineKeyboardButton.new(text: "🧹 Clear transport messages", callback_data: "bus_clear")]
        ]
      )
      Bot::Messaging.send_message(
        bot, chat_id,
        "Transport results ready. You can clear them below.",
        suppress_delete: true, reply_markup: kb, track: true, bucket: :bus
      )
    end

    def clear_transport_messages(bot, chat_id)
      key = Bot::Util.chid(chat_id)
      ids = Bot::Messaging.bus_msgs[key]
      return if ids.nil? || ids.empty?

      ids.each do |mid|
        begin
          bot.api.delete_message(chat_id: chat_id, message_id: mid)
        rescue Telegram::Bot::Exceptions::ResponseError
        end
      end
      Bot::Messaging.bus_msgs[key].clear
    end
  end
end
