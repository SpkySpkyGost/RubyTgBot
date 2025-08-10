# frozen_string_literal: true
# timer.rb
require "date"

module Timer
  START_DEFAULT = DateTime.new(2001, 5, 25, 0, 0, 0)
  END_DEFAULT   = DateTime.new(2031, 5, 25, 0, 0, 0)

  module_function

  def message(from: START_DEFAULT, to: END_DEFAULT, now: DateTime.now)
    if now >= to
      elapsed = diff_breakdown(from, to)
      return "⏳ *Countdown Timer*\n" \
        "Milestone *reached* on *25 May 2031*.\n" \
        "Since *25 May 2001*: _#{fmt(elapsed)}_"
    end

    elapsed   = diff_breakdown(from, now)
    remaining = diff_breakdown(now, to)

    "⏳ *Countdown Timer*\n" \
      "Since *25 May 2001*: _#{fmt(elapsed)}_\n" \
      "Until *25 May 2031*: _#{fmt(remaining)}_"
  end

  # --- helpers ---

  def diff_breakdown(a, b)
    # a, b are DateTime
    ay, am, ad = a.year, a.month, a.day
    by, bm, bd = b.year, b.month, b.day

    years  = by - ay
    months = bm - am
    days   = bd - ad

    if days < 0
      months -= 1
      days += days_in_prev_month(b)
    end

    if months < 0
      years -= 1
      months += 12
    end

    hours_total = ((b - a) * 24).to_i
    hours = hours_total % 24

    { years: years, months: months, days: days, hours: hours }
  end

  def days_in_prev_month(dt)
    prev = dt << 1 # previous month
    days_in_month(prev)
  end

  def days_in_month(dt)
    d1 = Date.new(dt.year, dt.month, 1)
    (d1.next_month - d1).to_i
  end

  def fmt(h)
    "#{h[:years]}y #{h[:months]}m #{h[:days]}d #{h[:hours]}h"
  end
end
