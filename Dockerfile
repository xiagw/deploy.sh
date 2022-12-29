FROM ubuntu:20.04

WORKDIR /runner

COPY . /runner/

RUN set -x \
    # && touch Dockerfile composer.json package.json pom.xml requirements.txt \
    && sed -i -e '/=false/s/false/true/g' conf/example-deploy.env \
    && sed -i -e '/ENV_INSTALL_JMETER=/s/true/false/' conf/example-deploy.env \
    && chmod +x ./deploy.sh \
    && ./deploy.sh --github-action