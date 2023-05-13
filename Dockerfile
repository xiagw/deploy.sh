FROM ubuntu:20.04

WORKDIR /runner

COPY . /runner/

RUN set -x \
    # && touch Dockerfile composer.json package.json pom.xml requirements.txt \
    && sed -i -e '/=false/s/false/true/g' /runner/conf/example-deploy.env \
    && sed -i -e '/ENV_INSTALL_JMETER=/s/true/false/' /runner/conf/example-deploy.env \
    && chmod +x /runner//deploy.sh \
    && /runner/deploy.sh --github-action