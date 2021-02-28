FROM alpine
RUN apk --update add gettext curl jq && \
  mkdir /dist
COPY entrypoint.sh /dist/entrypoint.sh
ENTRYPOINT [ "/dist/entrypoint.sh" ]
