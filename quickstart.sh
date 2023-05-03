#!/usr/bin/env bash
set -eE

UP_VERSION=v0.16.1

EMOJI_FAIL=❌
EMOJI_SUCCESS=✅
INSTALL_PATH_UP="/usr/local/bin"
SETUP_FOLDER=common
TIMEOUT=180s

apply_provider() {
  printf "Installing the provider (this will take a few minutes)...\n"
  kubectl apply -f "$SETUP_FOLDER"/provider.yaml

  echo "waiting for condition=Installed"
  kubectl wait "providers.pkg.crossplane.io/provider-aws" --for=condition=Installed --timeout="$TIMEOUT"
  
  echo "waiting for condition=Healthy"
  kubectl wait "providers.pkg.crossplane.io/provider-aws" --for=condition=Healthy --timeout="$TIMEOUT"
}

apply_provider_config(){
  kubectl apply -f "$SETUP_FOLDER"/providerConfig.yaml
}

apply_secret() {
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
}

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

get_aws_creds() {
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
}

get_creds_via_prompting() {
  read -p "AWS access_key_id: " aws_access_key; read -sp "AWS secret_access_key: " aws_secret_key; export AWS_KEY=$aws_access_key; export AWS_SECRET=$aws_secret_key; printf "\n"
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

install_up_cli() {
  if is_up_cli_installed; then 
    if [ $(up --version) != "$UP_VERSION" ]; then
      echo "up version at $(which up): $(up --version)"
      echo "remove up cli via 'rm $(which up)' and run this script again (script tested with $UP_VERSION)"
      exit 1
    else
      echo "$EMOJI_SUCCESS up $(up --version) already installed at $(which up)"
    fi
  else
    echo "Installing up CLI..."
    # curl -sL "https://cli.upbound.io" | sh >/dev/null
    mkdir -p "$INSTALL_PATH_UP"
    sudo mv up "$INSTALL_PATH_UP"
    if is_up_cli_installed; then
      echo "$EMOJI_SUCCESS up CLI installed to $INSTALL_PATH_UP"
    else
      echo "error installint up cli"
      return 1
    fi
  fi
}

install_uxp() {
  if ! kubectl -n upbound-system get deployment crossplane > /dev/null 2>&1; then printf "Installing UXP...\n" && up uxp install; fi

  printf "Checking the UXP installation (this only takes a minute)...\n"
  kubectl -n upbound-system wait deployment crossplane --for=condition=Available --timeout="$TIMEOUT"
}

is_up_cli_installed() {
  up --version > /dev/null 2>&1
}

get_aws_creds
install_up_cli
install_uxp
apply_provider
apply_secret
apply_provider_config