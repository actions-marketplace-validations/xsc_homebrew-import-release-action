FROM alpine
RUN apk --update add gettext jq && \
  mkdir /dist
COPY entrypoint.sh /dist/entrypoint.sh
ENTRYPOINT [ "/dist/entrypoint.sh" ]
