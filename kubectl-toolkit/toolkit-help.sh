#!/bin/bash

cbold='\033[1m'
cnone='\033[0m'

echo -e "How to use kubectl (aka k): ${cbold}https://kubernetes.io/docs/reference/kubectl/cheatsheet/#kubectl-apply${cnone}"
echo -e "How to edit k8s secret: ${cbold}kedit-secret \$SECRET_NAME${cnone} or ${cbold}kubectl-edit-secret \$SECRET_NAME${cnone}"
echo -e "Start mysql client with credentials from secret SECRET_NAME: ${cbold}k8s-mysql \$SECRET_NAME${cnone}"
echo -e "Start postgres client with credentials from secret SECRET_NAME: ${cbold}k8s-psql \$SECRET_NAME${cnone}"
echo -e "Run a kafka scripts with credentials from secret SECRET_NAME: ${cbold}k8s-kafka \$SECRET_NAME${cnone}"
echo -e "Retrieve secret as environment variables: ${cbold}k8s-secret \$SECRET_NAME [\$VAR_PREFIX]${cnone}"
echo -e "Listing bucket objects: ${cbold}bucket help${cnone}"
echo -e "Kubernetes TUI: ${cbold}k9s${cnone}"
