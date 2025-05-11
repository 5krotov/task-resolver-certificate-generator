#!/bin/bash
set -e

if [ $# -lt 3 ]; then
  echo "Usage: $0 <config_path> <output_dir> <service1> [<service2> ...]"
  echo "Example: $0 /config-path /certs service1 service2"
  exit 1
fi

CONFIG_PATH="$1"
OUTPUT_DIR="$2"
shift 2
SERVICES=("$@")

find "$OUTPUT_DIR/" -mindepth 1 -delete

mkdir "$OUTPUT_DIR/root/"
mkdir "$OUTPUT_DIR/internal/"

echo "Loading configurations from: $CONFIG_PATH"
echo "Saving certificates to: $OUTPUT_DIR"
echo "Processing services: ${SERVICES[*]}"

# Generate Root CA
openssl genrsa -out "$OUTPUT_DIR/root/root-ca.key" 4096
openssl req -new -x509 -days 3650 -key "$OUTPUT_DIR/root/root-ca.key" \
    -out "$OUTPUT_DIR/root/root-ca.crt" -config "$CONFIG_PATH/root/root-ca.conf"
openssl x509 -in "$OUTPUT_DIR/root/root-ca.crt" -out "$OUTPUT_DIR/root/root-ca.pem" -outform PEM

# Generate Intermediate CA
openssl genrsa -out "$OUTPUT_DIR/internal/internal-ca.key" 4096
openssl req -new -key "$OUTPUT_DIR/internal/internal-ca.key" \
    -out "$OUTPUT_DIR/internal/internal-ca.csr" -config "$CONFIG_PATH/internal/internal-ca.conf"
openssl x509 -req -days 1825 -in "$OUTPUT_DIR/internal/internal-ca.csr" \
    -CA "$OUTPUT_DIR/root/root-ca.crt" -CAkey "$OUTPUT_DIR/root/root-ca.key" -CAcreateserial \
    -out "$OUTPUT_DIR/internal/internal-ca.crt" -extfile "$CONFIG_PATH/internal/internal-ca.conf" -extensions v3_ca
openssl x509 -in "$OUTPUT_DIR/internal/internal-ca.crt" -out "$OUTPUT_DIR/internal/internal-ca.pem" -outform PEM

# Generate Services CA
for SERVICE in "${SERVICES[@]}"; do

  mkdir -p "$OUTPUT_DIR/$SERVICE/"

  SERVICE_CONF="$CONFIG_PATH/services/$SERVICE.conf"

  if [ ! -f "$SERVICE_CONF" ]; then
    echo "ERROR: Configuration file $SERVICE_CONF not found"
    exit 1
  fi

  echo "Generating certificate for service: $SERVICE (config: $SERVICE_CONF)"

  # Generate private key
  openssl genrsa -out "$OUTPUT_DIR/$SERVICE/$SERVICE.key" 2048

  # Generate CSR
  openssl req -new -key "$OUTPUT_DIR/$SERVICE/$SERVICE.key" \
      -out "$OUTPUT_DIR/$SERVICE/$SERVICE.csr" -config "$SERVICE_CONF"

  # Sign certificate with Intermediate CA
  openssl x509 -req -days 365 -in "$OUTPUT_DIR/$SERVICE/$SERVICE.csr" \
      -CA "$OUTPUT_DIR/internal/internal-ca.crt" -CAkey "$OUTPUT_DIR/internal/internal-ca.key" -CAcreateserial \
      -out "$OUTPUT_DIR/$SERVICE/$SERVICE.crt" -extfile "$SERVICE_CONF" -extensions v3_req

  openssl x509 -in "$OUTPUT_DIR/$SERVICE/$SERVICE.crt" -out "$OUTPUT_DIR/$SERVICE/$SERVICE.pem" -outform PEM
  openssl rsa -in "$OUTPUT_DIR/$SERVICE/$SERVICE.key" -out "$OUTPUT_DIR/$SERVICE/$SERVICE-key.pem" -outform PEM

  # Create certificate chain (service cert + Intermediate CA)
  cat "$OUTPUT_DIR/$SERVICE/$SERVICE.crt" "$OUTPUT_DIR/internal/internal-ca.crt" > "$OUTPUT_DIR/$SERVICE/$SERVICE-chain.crt"
  cat "$OUTPUT_DIR/$SERVICE/$SERVICE.pem" "$OUTPUT_DIR/internal/internal-ca.pem" > "$OUTPUT_DIR/$SERVICE/$SERVICE-chain.pem"
done

# Set proper file permissions
chmod 777 "$OUTPUT_DIR"/**/*.key
chmod 777 "$OUTPUT_DIR"/**/*.{crt,csr,pem}

echo "Certificate generation complete!"
echo "Root CA:       $OUTPUT_DIR/root/root-ca.{key,crt,pem}"
echo "Intermediate CA:   $OUTPUT_DIR/internal/internal-ca.{key,crt,pem}"
echo "Service files:"
echo "  Private key: $OUTPUT_DIR/<service-name>/<service-name>.{key,pem}"
echo "  Certificate: $OUTPUT_DIR/<service-name>/<service-name>.{crt,pem}"
echo "  Chain file:  $OUTPUT_DIR/<service-name>/<service-name>-chain.{crt,pem}"