FROM ubuntu:20.04

COPY . /runner/

RUN /runner/deploy.sh