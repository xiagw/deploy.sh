FROM ubuntu:20.04

COPY . /runner/

RUN set -xe ; chmod +x /runner/deploy.sh ; /runner/deploy.sh --debug