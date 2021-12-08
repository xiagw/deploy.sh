FROM ubuntu:20.04

WORKDIR /runner

COPY . /runner/

RUN set -xe \
    && touch Dockerfile composer.json package.json pom.xml requirements.txt \
    && sed -i -e '/=false/s/false/true/g' conf/deploy.env.example \
    && sed -i -e '/ENV_INSTALL_JMETER=false/s/true/false/' conf/deploy.env.example \
    && chmod +x ./deploy.sh \
    && ./deploy.sh --github