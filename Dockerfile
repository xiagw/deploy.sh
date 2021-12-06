FROM ubuntu:20.04

WORKDIR /runner

COPY . /runner/

RUN set -xe ; chmod +x /runner/deploy.sh ; /runner/deploy.sh --github