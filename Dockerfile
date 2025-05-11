FROM alpine:3.18

RUN apk add --no-cache openssl bash

WORKDIR /app
COPY generate-certs.sh .
RUN chmod +x generate-certs.sh

VOLUME ["/configs", "/certs"]

ENTRYPOINT ["/app/generate-certs.sh"]
CMD ["--help"]