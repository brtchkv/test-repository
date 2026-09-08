kubectl toolkit
====

Universal container with kubectl + database clients + cli tools. Developed for and used in JetBrains Cloud Console.

### Examples

See [examples dir](./examples)

### How to use

Start container in kubernetes, mount serviceaccount. After that kubectl will work with serviceaccount access.

- Use kubernetes: `kubectl ...` (see [cheatsheet](https://kubernetes.io/docs/reference/kubectl/cheatsheet/#kubectl-apply))
- Start mysql client with creds from secret `SECRET_NAME`: `k8s-mysql $SECRET_NAME` (see [k8s-mysql.sh](./k8s-mysql.sh))
- Start postgres client with creds from secret `SECRET_NAME`: `k8s-psql $SECRET_NAME` (see [k8s-psql.sh](./k8s-psql.sh))
- Run a kafka scripts tool with creds from secret `SECRET_NAME` (a `KafkaUser` secret): `k8s-kafka $SECRET_NAME` (see [k8s-kafka.sh](./k8s-kafka.sh)). The secret is read at run time with the serviceaccount - nothing needs to be mounted. Tools: `topics`, `console-producer`, `console-consumer`, `consumer-groups`, `groups`, `get-offsets`, `log-dirs`, `transactions`, `broker-api-versions`, `acls`
- Load data from secret `SECRET_NAME` as environment variables with prefix `VAR_PREFIX` (optional): `k8s-secret $SECRET_NAME $VAR_PREFIX` (see [k8s-secret.sh](./k8s-secret.sh))
- Working with bucket via `bucket` (see `bucket help` or [bucket.sh](./bucket.sh)) command or `s3cmd` directly.

### Lifetime of the container

If no input and output happened after `$IDLE_TIMEOUT` seconds container will be exited with status 0 (see [watcher.sh](./watcher.sh)).

### Manual build

```
docker buildx create --use
docker buildx inspect --bootstrap
docker buildx build --progress plain --platform linux/amd64,linux/arm64 -t registry.jetbrains.team/p/kitd/public/kubectl-toolkit:XXXX --push .
```