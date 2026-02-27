FROM ruby:3.4-slim

WORKDIR /app

RUN apt-get update && apt-get install -y \
    git \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

COPY Gemfile Gemfile.lock betters3tui.gemspec ./
COPY lib/ ./lib/
COPY bin/ ./bin/

RUN bundle install

RUN chmod +x bin/betters3tui

ENTRYPOINT ["ruby", "bin/betters3tui"]
