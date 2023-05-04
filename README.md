# Knowledge Share - Crossplane Parts 1 & 2
  Repo to accompany the talks given as part of the "Month of IDP (Internal Developer Platform)" series, May 2023

## setup

  ### pre-requisites:
  - A Kubernetes cluster (some common local micro distros include: [K3D](k3d.io), [KIND](https://kind.sigs.k8s.io/), [Minikube](https://minikube.sigs.k8s.io/docs/start/))
  
  - Account credentials:
    - AWS: [access_key_id & secret_access_key](https://docs.aws.amazon.com/powershell/latest/userguide/pstools-appendix-sign-up.html). The quickstart.sh script will read these creds from (in this order):
      - environment variables: AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY
      - AWS credentials file (profile default, path: $HOME/.aws/credentials)
      - prompts directly if unable to find from above

  ### run
  `./quickstart.sh [aws_profile_name] [aws_credentials_file]`

## structure

  ### common
    contains provider and providerConfig declarations which can be used for all examples

  ### part_1/packages

    - 01_bucket: create a simple S3 bucket in region eu-north-1
      ```
      kubectl apply -f part_1/packages/01_bucket/src --recursive
      ```

## packages - sample workflow
  ```
  # Build
  up xpkg build --output=hello-bucket.xpkg
  docker load -i hello-bucket.xpkg

  # Push to Registry
  aws ecr get-login-password --region eu-north-1 | docker login --username AWS --password-stdin public.ecr.aws/h6b3h6y7
  docker tag [sha from load command] public.ecr.aws/h6b3h6y7/xplane_test_v0.1.0
  docker push public.ecr.aws/h6b3h6y7/xplane_test_v0.1.0
  
  # Deploy
  kubectl apply -f part_1/packages/01_bucket/xpkg.yaml
  ```


## status check:

`watch kubectl get provider,providerConfig,xrd,composition,xhello,Bucket.s3`