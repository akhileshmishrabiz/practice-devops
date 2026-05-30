FROM alpine:3.19

RUN apk add --no-cache curl bash python3

WORKDIR /app

COPY seed-data.sh .
RUN chmod +x seed-data.sh

CMD ["./seed-data.sh"]
