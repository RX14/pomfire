FROM crystallang/crystal:0.23.1

ARG uid=9703
ARG gid=9703

RUN useradd --system -u $uid -U pomfire

CMD ["/pomfire"]

ADD . /src
RUN cd /src \
 && shards build \
 && mv bin/pomfire / \
 && cd / && rm -Rf /src

USER pomfire

