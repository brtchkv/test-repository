# syntax=docker/dockerfile:1

FROM alpine:3.19

# Mount both secrets and print their values to confirm they are available.
# Secrets are read from the BuildKit tmpfs mount and are NOT baked into the image layer.
RUN --mount=type=secret,id=MY_SECRET_1 \
    --mount=type=secret,id=MY_SECRET_2 \
    MY_SECRET_1=$(cat /run/secrets/MY_SECRET_1) && \
    MY_SECRET_2=$(cat /run/secrets/MY_SECRET_2) && \
    echo "MY_SECRET_1 value: ${MY_SECRET_1}" && \
    echo "MY_SECRET_2 value: ${MY_SECRET_2}" && \
    echo "Both secrets successfully received."

CMD ["echo", "Container started successfully"]
