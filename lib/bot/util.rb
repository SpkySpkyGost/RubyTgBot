# frozen_string_literal: true
require "cgi"

module Bot
  module Util
    module_function

    # Simple HTML escape helper
    def html_escape(s)
      CGI.escapeHTML(s.to_s)
    end

    # chat id -> consistent string key
    def chid(id) id.to_s end
  end
end
