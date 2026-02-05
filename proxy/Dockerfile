FROM ruby:3.3-slim
WORKDIR /app
COPY Gemfile ./
RUN bundle install
COPY config.ru ./
ENV PORT=8080
EXPOSE 8080
CMD ["bundle", "exec", "rackup", "-o", "0.0.0.0", "-p", "8080"]
