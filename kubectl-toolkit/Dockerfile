# START OF KAFKA BUILD
FROM alpine:3.23 AS kafka-tools

ARG KAFKA_VERSION=4.3.1
ARG SCALA_VERSION=2.13
ARG TARGETARCH

# Kafka Debug CLI tools. kafka-run-class.sh is the launcher used by all of them.
# kafka-configs.sh is deliberately NOT shipped: it is still Scala (kafka.admin.ConfigCommand)
# and would drag in scala-library + core + coordinator jars
ARG KAFKA_BIN="kafka-run-class.sh \
      kafka-topics.sh \
      kafka-console-producer.sh \
      kafka-console-consumer.sh \
      kafka-consumer-groups.sh \
      kafka-get-offsets.sh \
      kafka-groups.sh \
      kafka-log-dirs.sh \
      kafka-transactions.sh \
      kafka-broker-api-versions.sh \
      kafka-acls.sh"
ARG KAFKA_LIBS="argparse4j-*.jar \
      jackson-annotations-*.jar \
      jackson-core-*.jar \
      jackson-databind-*.jar \
      jackson-dataformat-yaml-*.jar \
      jakarta.servlet-api-*.jar \
      jopt-simple-*.jar \
      jose4j-*.jar \
      jspecify-*.jar \
      kafka-clients-*.jar \
      kafka-server-[0-9]*.jar \
      kafka-server-common-*.jar \
      kafka-storage-[0-9]*.jar \
      kafka-tools-[0-9]*.jar \
      kafka-tools-api-*.jar \
      log4j-1.2-api-*.jar \
      log4j-api-*.jar \
      log4j-core-*.jar \
      log4j-slf4j-impl-*.jar \
      lz4-java-*.jar \
      re2j-*.jar \
      slf4j-api-*.jar \
      snakeyaml-*.jar \
      snappy-java-*.jar \
      zstd-jni-*.jar"

RUN apk add --no-cache \
      openjdk21-jdk \
      binutils \
      curl \
      tar \
      zip \
      unzip

RUN curl -fL \
      "https://downloads.apache.org/kafka/${KAFKA_VERSION}/kafka_${SCALA_VERSION}-${KAFKA_VERSION}.tgz" \
      -o /tmp/kafka.tgz \
    && mkdir -p /opt \
    && tar -xzf /tmp/kafka.tgz -C /opt \
    && rm /tmp/kafka.tgz

# java.desktop is required by log4j-core (LoggerContext implements java.beans.PropertyChangeListener), jdk.crypto.ec by
# TLS 1.3 key exchange, jdk.security.auth by the JAAS config used for SASL, java.security.sasl
# and java.security.jgss by SASL/Kerberos, jdk.unsupported by lz4/kafka-clients (sun.misc.Unsafe)
RUN jlink \
      --add-modules java.base,java.desktop,java.logging,java.management,java.naming,java.security.jgss,java.security.sasl,java.sql,jdk.crypto.ec,jdk.net,jdk.security.auth,jdk.unsupported \
      --exclude-files='glob:/java.desktop/lib/*.so' \
      --strip-debug \
      --no-man-pages \
      --no-header-files \
      --compress=zip-6 \
      --output /opt/java

RUN set -eu; \
    src="/opt/kafka_${SCALA_VERSION}-${KAFKA_VERSION}"; \
    mkdir -p /opt/kafka-cli/bin /opt/kafka-cli/config /opt/kafka-cli/libs; \
    for s in ${KAFKA_BIN}; do \
      cp "${src}/bin/${s}" /opt/kafka-cli/bin/; \
    done; \
    cp "${src}/config/tools-log4j2.yaml" /opt/kafka-cli/config/; \
    for p in ${KAFKA_LIBS}; do \
      set -- ${src}/libs/${p}; \
      [ -e "$1" ] || { echo "ERROR: no jar matches '${p}' in ${src}/libs" >&2; exit 1; }; \
      cp "$@" /opt/kafka-cli/libs/; \
    done
# END OF KAFKA BUILD

FROM alpine:3.23

# libc6-compat needed for Kafka
RUN apk update && apk upgrade && \
    apk add --update --no-cache vim bash-completion less zip unzip jq curl wget bind-tools iputils-ping traceroute \
    busybox-extras openssl mysql-client postgresql-client s3cmd redis \
    python3 py-pip py-cffi py-cryptography py3-yaml libc6-compat

RUN apk add --virtual build-deps \
      gcc \
      libffi-dev \
      python3-dev \
      linux-headers \
      musl-dev \
      openssl-dev \
    && pip3 install --break-system-packages gsutil \
    && apk del build-deps \
    && curl -L https://raw.githubusercontent.com/lbolla/kube-secret-editor/a980fd6537b5d2155bb3e413d40b9adc7fb08d6b/kube-secret-editor.py -o /opt/kube-secret-editor.py

COPY --from=kafka-tools /opt/java /opt/java
COPY --from=kafka-tools /opt/kafka-cli /opt/kafka

ENV JAVA_HOME=/opt/java
ENV KAFKA_HOME=/opt/kafka
ENV PATH="/opt/java/bin:/opt/kafka/bin:${PATH}"

# Disable JMX options because the jlink runtime intentionally excludes
# JMX/JFR-related modules that are not needed for CLI usage
ENV KAFKA_JMX_OPTS=" "

COPY watcher.sh /bin/container-watcher
COPY k8s-mysql.sh /bin/k8s-mysql
COPY k8s-psql.sh /bin/k8s-psql
COPY k8s-secret.sh /bin/k8s-secret
COPY k8s-kafka.sh /bin/k8s-kafka
COPY k8s-bash.sh /bin/k8s-bash
COPY bucket.sh /bin/bucket
COPY k9s.sh /bin/k9s
COPY toolkit-help.sh /bin/toolkit-help

COPY psql/create.sh /bin/psql-backup
COPY psql/restore.sh /bin/psql-restore
COPY mysql/create.sh /bin/mysql-backup
COPY mysql/restore.sh /bin/mysql-restore

RUN chmod +x /bin/container-watcher \
    /bin/k8s-mysql /bin/k8s-psql /bin/k8s-kafka /bin/k8s-secret /bin/k8s-bash \
    /bin/bucket /bin/k9s /bin/toolkit-help /bin/psql-backup /bin/psql-restore /bin/mysql-backup /bin/mysql-restore \
    /opt/kube-secret-editor.py

RUN adduser -s /bin/bash -u 1001 -D -g kubectl kubectl

ARG TARGETARCH

# see https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/
RUN curl -L -f -o /bin/kubectl https://dl.k8s.io/release/v1.34.9/bin/linux/${TARGETARCH}/kubectl && chmod +x /bin/kubectl

# see https://github.com/derailed/k9s/releases
RUN curl -L -f https://github.com/derailed/k9s/releases/download/v0.50.18/k9s_Linux_${TARGETARCH}.tar.gz | tar -xz -C /tmp && \
    mv /tmp/k9s /bin/k9s-bin && chmod +x /bin/k9s-bin

RUN kubectl completion bash > /usr/share/bash-completion/completions/kubectl && \
    sed -r 's/complete(.*)kubectl/complete\1kubectl k/g' -i /usr/share/bash-completion/completions/kubectl
ADD bash_completion/bucket /usr/share/bash-completion/completions/bucket

# switch to kubectl user using uid to avoid k8s validation failure
USER 1001
WORKDIR /home/kubectl

COPY bashrc /home/kubectl/.bashrc

# for local use and/or testing
VOLUME /home/kubectl/.kube

# idle timeout in seconds
ENV IDLE_TIMEOUT=3600

CMD ["/bin/container-watcher"]
