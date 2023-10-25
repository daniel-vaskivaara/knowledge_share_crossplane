#!/bin/bash -ex

curl -sL "https://cli.upbound.io" | sh
sudo mv up /usr/local/bin/
up --version
up uxp install

kubectl wait pod \
--all \
--for=condition=Ready \
--namespace="upbound-system"

kubectl apply -f provider.yaml

az login
# # # ADD <Subscription ID> then uncomment following line: # # #
#az ad sp create-for-rbac --sdk-auth --role Owner --scopes /subscriptions/<Subscription ID> 

kubectl create secret \
  generic azure-secret \
  -n "upbound-system" \
  --from-file=creds=./azure-credentials.json

kubectl apply -f providerConfig.yaml

# feel free to change the password, but fair warning you may get warnings if it's too short / simple
kubectl create secret generic mssqlserver --from-literal=FJ8I1x0YW0um5fNm2o92c9lK6W75VNI8 -n upbound-system

kubectl apply -f resources