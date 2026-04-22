# syntax=docker/dockerfile:1

FROM alpine:3.19

# Mount both secrets and print their values to confirm they are available.
# Secrets are read from the BuildKit tmpfs mount and are NOT baked into the image layer.
RUN --mount=type=secret,id=MY_SECRET_1,env=MY_SECRET_1 \
    --mount=type=secret,id=MY_SECRET_2,env=MY_SECRET_2 \
    echo "MY_SECRET_1 length: ${#MY_SECRET_1}" && \
    echo "MY_SECRET_2 length: ${#MY_SECRET_2}"

CMD ["echo", "Container started successfully"]
