# frozen_string_literal: true

require_relative "http"
require_relative "messaging"
require_relative "rec"
require_relative "csv_store"
require_relative "music_helpers"
require_relative "transport"
require_relative "report"
require_relative "broadcast"
require_relative "util"
module Bot
  # convenience includes for files that want bare method calls:
  def self.included(base)
    base.include Util
    base.include HTTP
    base.include Messaging
    base.include Rec
    base.include CSVStore
    base.include MusicHelpers
    base.include Transport
    base.include Report
    base.include Broadcast
  end
end
