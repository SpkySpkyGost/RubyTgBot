# frozen_string_literal: true
require "csv"
require "time"

module Bot
  module CSVStore
    module_function

    def subscribed?(user_id)
      !get_user_city(user_id).to_s.strip.empty?
    end

    def add_user_if_missing(user_id)
      rows = CSV.read(USERS_CSV, headers: true)
      if rows.any? { |row| row["user_id"] == user_id.to_s }
        update_last_start(user_id)
      else
        CSV.open(USERS_CSV, "a") { |csv| csv << [user_id, nil, Time.now.utc.iso8601] }
      end
    end

    def update_last_start(user_id)
      table = CSV.table(USERS_CSV)
      table.each { |row| row[:last_start] = Time.now.utc.iso8601 if row[:user_id].to_s == user_id.to_s }
      File.write(USERS_CSV, table.to_csv)
    end

    def update_city(user_id, city)
      table = CSV.table(USERS_CSV)
      table.each { |row| row[:city] = city if row[:user_id].to_s == user_id.to_s }
      File.write(USERS_CSV, table.to_csv)
    end

    def get_user_last_start(user_id)
      row = CSV.read(USERS_CSV, headers: true).find { |r| r["user_id"] == user_id.to_s }
      row && row["last_start"] ? Time.parse(row["last_start"]) : nil
    end

    def get_user_city(user_id)
      row = CSV.read(USERS_CSV, headers: true).find { |r| r["user_id"] == user_id.to_s }
      row ? (row["city"] || "").strip : ""
    end

    def all_user_rows
      CSV.read(USERS_CSV, headers: true)
    end
  end
end
