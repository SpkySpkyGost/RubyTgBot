FROM ruby:3.4-bookworm

ENV LANG=C.UTF-8 \
    TZ=Europe/Prague \
    APP_HOME=/app \
    PLAYWRIGHT_BROWSERS_PATH=/ms-playwright

# 1) Node.js (needed by the Playwright CLI)
RUN apt-get update && apt-get install -y curl ca-certificates gnupg && \
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get install -y nodejs && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

# 2) Ruby deps first (better layer caching)
COPY Gemfile Gemfile.lock ./
RUN bundle install

# 3) App files
COPY . .

# 4) Install Playwright + Chromium + required OS libs
#    (--with-deps pulls in the libnss3/libatk/etc automatically)
RUN npm i -D playwright && npx playwright install --with-deps chromium

CMD ["ruby", "main.rb"]
