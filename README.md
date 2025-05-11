# task-resolver-certificate-generator

## Build
```bash
  docker build -t certificate-generator .
```

## Generate
```bash
  mkdir certs
  docker run --rm -v ./configs:/configs -v ./certs:/certs certificate-generator /configs /certs api-service agent-service data-provider-service
```