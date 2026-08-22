# Multi-stage: bygg gems i builder-stadiet, kopier til slank runtime.
FROM ruby:3.3-slim AS builder
WORKDIR /app
RUN apt-get update && apt-get install -y --no-install-recommends build-essential pkg-config libsqlite3-dev \
  && rm -rf /var/lib/apt/lists/*
COPY Gemfile Gemfile.lock ./
RUN bundle config set --local deployment true \
  && bundle install --jobs 4 --retry 3

FROM ruby:3.3-slim
WORKDIR /app
RUN apt-get update && apt-get install -y --no-install-recommends libsqlite3-0 tzdata ca-certificates \
  && rm -rf /var/lib/apt/lists/*
ENV TZ=Europe/Oslo
ENV RACK_ENV=production
ENV PORT=8080
COPY --from=builder /usr/local/bundle /usr/local/bundle
COPY . .
RUN mkdir -p /app/data
EXPOSE 8080
# Leser PORT fra miljøet (Fly.io/Render setter denne).
CMD ["sh", "-c", "bundle exec puma -b tcp://0.0.0.0:${PORT:-8080}"]