#!/usr/bin/env bash
set -eE

are_aws_env_creds_set() {
  #if [ -n "$AWS_ACCESS_KEY_ID" ] && [ -n "$AWS_SECRET_ACCESS_KEY" ]; then
  if [ -n "${AWS_ACCESS_KEY_ID+x}" ] && \
     [ -n "${AWS_SECRET_ACCESS_KEY+x}" ] && \
     [ -n "$(echo -e "${AWS_ACCESS_KEY_ID}\n${AWS_SECRET_ACCESS_KEY}" | sed '/^\s*$/d')" ]; then
    return 0
  else
    return 1
  fi
}

import_from_file_sections() {
    # parses a file and looks for sections delimited by '[section_name]', then reads 
    # all variables in the form of 'variable = value', after stripping out any spaces
    local section="${1:-default}"
    local config_file="${2:-$HOME/.aws/credentials}"

    while read line; do
      # Check if the line starts with the section name in brackets
      if [[ "$line" =~ ^\[$section\] ]]; then
          # Set the flag to start reading variables
          read_vars="true"
      elif [[ "$line" =~ ^\[.*\] ]]; then
          # Set the flag to stop reading variables if a new section is encountered
          read_vars=""
      elif [[ "$read_vars" == "true" ]]; then
          # Stip empty spaces then check for non-null
          stripped_input=$(echo "$line" | tr -d ' ')
          if [ -z "$stripped_input" ]; then break; fi

          # Read the variables if the flag is set
          var_name=$(echo "$stripped_input" | cut -d'=' -f1)
          var_value=$(echo "$stripped_input" | cut -d'=' -f2)

          export "$var_name"="$var_value"
      fi
    done < "$config_file"
}

get_creds_via_prompting() {
  read -p "AWS access_key_id: " aws_access_key; read -sp "AWS secret_access_key: " aws_secret_key; export AWS_KEY=$aws_access_key; export AWS_SECRET=$aws_secret_key; printf "\n"
}

unset AWS_KEY AWS_SECRET
if are_aws_env_creds_set; then
  echo "using credentials from environment"
  export AWS_KEY="$AWS_ACCESS_KEY_ID"
  export AWS_SECRET="$AWS_SECRET_ACCESS_KEY"
else
  import_from_file_sections
  if [ -n "$aws_access_key_id" ] && [ -n "$aws_secret_access_key" ]; then
    echo "using credentials from aws credentials file"
    export AWS_KEY="$aws_access_key_id"
    export AWS_SECRET="$aws_secret_access_key"
  else
    get_creds_via_prompting
  fi
fi

if ! up --version > /dev/null 2>&1; then printf "Installing up CLI...\n"; curl -sL "https://cli.upbound.io" | sh; sudo mv up /usr/local/bin/; fi

if ! kubectl -n upbound-system get deployment crossplane > /dev/null 2>&1; then printf "Installing UXP...\n" && up uxp install; fi

printf "Checking the UXP installation (this only takes a minute)...\n"
kubectl -n upbound-system wait deployment crossplane --for=condition=Available --timeout=180s


printf "Installing the provider (this will take a few minutes)...\n"
cat <<EOF | kubectl apply -f -
apiVersion: pkg.crossplane.io/v1
kind: Provider
metadata:
  name: provider-aws
spec:
  package: xpkg.upbound.io/upbound/provider-aws:v0.21.0
EOF
kubectl wait "providers.pkg.crossplane.io/provider-aws" --for=condition=Installed --timeout=180s
kubectl wait "providers.pkg.crossplane.io/provider-aws" --for=condition=Healthy --timeout=180s



cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: aws-secret
  namespace: upbound-system
stringData:
  creds: |
    $(printf "[default]\n    aws_access_key_id = %s\n    aws_secret_access_key = %s" "${AWS_KEY}" "${AWS_SECRET}")
EOF

cat <<EOF | kubectl apply -f -
apiVersion: aws.upbound.io/v1beta1
kind: ProviderConfig
metadata:
  name: default