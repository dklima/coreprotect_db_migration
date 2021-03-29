FROM ruby:3.0

LABEL maintainer="dklima@gmail.com"
RUN apt-get update -yqq
RUN apt-get upgrade -yqq

COPY Gemfile* /app/
WORKDIR /app
RUN bundle install
COPY . /app/

CMD ["ruby", "migration.rb"]
