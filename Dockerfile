FROM ruby:alpine

RUN mkdir -p /usr/src/app
WORKDIR /usr/src/app

RUN ( apk update && apk add git )

COPY Gemfile /usr/src/app/
COPY Gemfile.lock /usr/src/app/
RUN bundle install

COPY . /usr/src/app

ENTRYPOINT ["/usr/src/app/git-sync"]

