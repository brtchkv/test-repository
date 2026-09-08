#!/bin/bash

# Runs a Kafka CLI tool with credentials from a KafkaUser secret. The secret is read at run
# time with the pod's serviceaccount - nothing needs to be mounted (same idea as k8s-psql)

set -eo pipefail

usage() {
  cat <<'EOF'
usage: k8s-kafka SECRET_NAME [TOOL [ARGS...]]

TOOL is a kafka-*.sh name without the prefix and the suffix, e.g. topics, console-producer,
console-consumer, consumer-groups, get-offsets. Without TOOL, only the client config is
written

Secret keys, as written by the kafka-controller for a KafkaUser: KAFKA_BOOTSTRAP_SERVERS,
KAFKA_SASL_USERNAME, KAFKA_SASL_PASSWORD, and optionally KAFKA_SECURITY_PROTOCOL (default
SASL_SSL) and KAFKA_SASL_MECHANISM (default SCRAM-SHA-512).

env KUBECTL_OPTIONS           - extra kubectl options, e.g. "-n my-namespace"
env KAFKA_CLIENT_EXTRA_CONFIG - extra client.properties lines, newline separated

examples:
  k8s-kafka my-kafka-credentials topics --list
  k8s-kafka my-kafka-credentials console-consumer --topic my.topic --from-beginning --max-messages 10
  echo 'k:v' | k8s-kafka my-kafka-credentials console-producer --topic my.topic \
    --reader-property parse.key=true --reader-property key.separator=:
EOF
}

case "$1" in
  -h | --help) usage; exit 0 ;;
  "") usage >&2; exit 1 ;;
esac

SECRET_NAME="$1"

echo "Reading Kafka credentials from secret $SECRET_NAME"
SECRET_DATA=$(kubectl $KUBECTL_OPTIONS get secret "$SECRET_NAME" -o json | jq -r '.data')
eval $( echo $SECRET_DATA | jq -r 'to_entries | map("\(.key|ascii_upcase|gsub("[^a-zA-Z0-9]+"; "_"))=\(.value|@base64d|@sh)") | .[]')

if [ -z "$KAFKA_BOOTSTRAP_SERVERS" ] || [ -z "$KAFKA_SASL_USERNAME" ] || [ -z "$KAFKA_SASL_PASSWORD" ]; then
  echo "ERROR: '$SECRET_NAME' is not a KafkaUser secret, its keys are:" \
       "$(echo $SECRET_DATA | jq -r 'keys | join(", ")')" >&2
  exit 1
fi
unset SECRET_DATA

case "${KAFKA_SASL_MECHANISM:=SCRAM-SHA-512}" in
  SCRAM-SHA-*) MODULE="scram.ScramLoginModule" ;;
  PLAIN)       MODULE="plain.PlainLoginModule" ;;
  *) echo "ERROR: unsupported mechanism $KAFKA_SASL_MECHANISM" \
          "(AWS_MSK_IAM needs the aws-msk-iam-auth jar, which this image does not ship)" >&2
     exit 1 ;;
esac

# escape \ and " for the jaas value - controller-generated passwords are [A-Za-z0-9-_], a hand-made secret may hold anything
jaas() { printf '%s' "$1" | sed 's/[\\"]/\\&/g'; }

umask 077
CONFIG="/tmp/kafka-client/$SECRET_NAME.properties"
mkdir -p "$(dirname "$CONFIG")"
cat > "$CONFIG" <<EOF
security.protocol=${KAFKA_SECURITY_PROTOCOL:-SASL_SSL}
sasl.mechanism=$KAFKA_SASL_MECHANISM
sasl.jaas.config=org.apache.kafka.common.security.$MODULE required username="$(jaas "$KAFKA_SASL_USERNAME")" password="$(jaas "$KAFKA_SASL_PASSWORD")";
$KAFKA_CLIENT_EXTRA_CONFIG
EOF
unset KAFKA_SASL_PASSWORD

if [ -z "$2" ]; then
  echo "config:  $CONFIG (mode 600, holds the password)"
  echo "brokers: $KAFKA_BOOTSTRAP_SERVERS"
  echo "example: kafka-topics.sh --bootstrap-server $KAFKA_BOOTSTRAP_SERVERS --command-config $CONFIG --list"
  exit 0
fi

if ! command -v "kafka-$2.sh" > /dev/null; then
  echo "ERROR: no kafka-$2.sh in this image, available tools:" >&2
  ls "$KAFKA_HOME/bin" | sed -e 's/^kafka-//' -e 's/\.sh$//' -e '/run-class/d' | tr '\n' ' ' >&2
  echo >&2
  exit 1
fi

exec "kafka-$2.sh" \
  --bootstrap-server "$KAFKA_BOOTSTRAP_SERVERS" \
  --command-config "$CONFIG" \
  "${@:3}"