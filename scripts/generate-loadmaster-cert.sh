#!/usr/bin/env bash
# Generate PEM certificate artifacts for a LoadMaster from the local intermediate CA.

set -euo pipefail
umask 077

CA_DIR=/root/myCA
NAME=
OUTPUT_DIR=
DNS_NAMES=()
IP_ADDRESSES=()

usage() {
  cat <<'EOF'
Usage: sudo generate-loadmaster-cert.sh --name NAME --output-dir DIRECTORY \
  --dns FQDN --ip ADDRESS [--dns FQDN] [--ip ADDRESS] [--ca-dir DIRECTORY]

Required arguments:
  --name NAME             Safe certificate artifact name (letters, digits, . _ -)
  --output-dir DIRECTORY  New directory for the generated PEM files
  --dns FQDN              DNS subject alternative name; may be repeated
  --ip ADDRESS            IPv4 or IPv6 subject alternative name; may be repeated

Optional arguments:
  --ca-dir DIRECTORY      Local CA directory (default: /root/myCA)
  -h, --help              Display this help text

The command produces server.key, server.crt, intermediate-chain.crt,
fullchain.crt, and manifest.txt. It will not overwrite existing artifacts.
EOF
}

require_value() {
  if [[ $# -lt 2 || -z $2 ]]; then
    printf 'ERROR: %s requires a value.\n' "$1" >&2
    exit 2
  fi
}

while [[ $# -gt 0 ]]; do
  case $1 in
    --name)
      require_value "$1" "${2:-}"
      NAME=$2
      shift 2
      ;;
    --output-dir)
      require_value "$1" "${2:-}"
      OUTPUT_DIR=$2
      shift 2
      ;;
    --dns)
      require_value "$1" "${2:-}"
      DNS_NAMES+=("$2")
      shift 2
      ;;
    --ip)
      require_value "$1" "${2:-}"
      IP_ADDRESSES+=("$2")
      shift 2
      ;;
    --ca-dir)
      require_value "$1" "${2:-}"
      CA_DIR=$2
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'ERROR: Unknown argument: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ $(id -u) -ne 0 ]]; then
  printf 'ERROR: Run this command as root so the CA private key remains protected.\n' >&2
  exit 1
fi

if [[ -z ${SUDO_UID:-} || -z ${SUDO_GID:-} ]]; then
  printf 'ERROR: Run this command through sudo so generated private-key artifacts can be assigned to the caller.\n' >&2
  exit 1
fi

if [[ -z $NAME || -z $OUTPUT_DIR || ${#DNS_NAMES[@]} -eq 0 || ${#IP_ADDRESSES[@]} -eq 0 ]]; then
  printf 'ERROR: --name, --output-dir, at least one --dns, and at least one --ip are required.\n' >&2
  usage >&2
  exit 2
fi

if [[ ! $NAME =~ ^[A-Za-z0-9._-]+$ ]]; then
  printf 'ERROR: --name may contain only letters, digits, periods, underscores, and hyphens.\n' >&2
  exit 2
fi

for dns_name in "${DNS_NAMES[@]}"; do
  if [[ ! $dns_name =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ ]]; then
    printf 'ERROR: Invalid DNS name: %s\n' "$dns_name" >&2
    exit 2
  fi
done

for ip_address in "${IP_ADDRESSES[@]}"; do
  if ! [[ $ip_address =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ || $ip_address == *:* ]]; then
    printf 'ERROR: Invalid IP address: %s\n' "$ip_address" >&2
    exit 2
  fi
done

ICA_CERT="$CA_DIR/intermediateCA/certs/intermediate.cert.pem"
ICA_CHAIN="$CA_DIR/intermediateCA/certs/intermediate.chain.pem"
ICA_KEY="$CA_DIR/intermediateCA/private/intermediate.key.pem"
ROOT_CERT="$CA_DIR/rootCA/certs/ca.cert.pem"

for required_file in "$ICA_CERT" "$ICA_CHAIN" "$ICA_KEY" "$ROOT_CERT"; do
  if [[ ! -f $required_file ]]; then
    printf 'ERROR: Required CA file not found: %s\n' "$required_file" >&2
    exit 1
  fi
done

if [[ -e $OUTPUT_DIR ]]; then
  printf 'ERROR: Output directory already exists: %s\n' "$OUTPUT_DIR" >&2
  exit 1
fi

mkdir -m 700 -- "$OUTPUT_DIR"
trap 'rm -rf -- "$OUTPUT_DIR"' ERR

config_file="$OUTPUT_DIR/openssl.cnf"
key_file="$OUTPUT_DIR/server.key"
csr_file="$OUTPUT_DIR/server.csr"
certificate_file="$OUTPUT_DIR/server.crt"
chain_file="$OUTPUT_DIR/intermediate-chain.crt"
fullchain_file="$OUTPUT_DIR/fullchain.crt"
manifest_file="$OUTPUT_DIR/manifest.txt"

san_entries=()
for dns_name in "${DNS_NAMES[@]}"; do san_entries+=("DNS:$dns_name"); done
for ip_address in "${IP_ADDRESSES[@]}"; do san_entries+=("IP:$ip_address"); done
SAN_VALUE=$(IFS=,; printf '%s' "${san_entries[*]}")

printf '%s\n' \
  '[req]' \
  'distinguished_name = subject' \
  'req_extensions = extensions' \
  'prompt = no' \
  '' \
  '[subject]' \
  "CN = ${DNS_NAMES[0]}" \
  '' \
  '[extensions]' \
  'basicConstraints = critical,CA:FALSE' \
  'keyUsage = critical,digitalSignature,keyEncipherment' \
  'extendedKeyUsage = serverAuth' \
  "subjectAltName = $SAN_VALUE" > "$config_file"

openssl req -new -newkey rsa:3072 -nodes \
  -keyout "$key_file" -out "$csr_file" -config "$config_file" -sha256
openssl x509 -req -in "$csr_file" -CA "$ICA_CERT" -CAkey "$ICA_KEY" \
  -CAcreateserial -out "$certificate_file" -days 365 -sha256 \
  -extfile "$config_file" -extensions extensions
cp -- "$ICA_CHAIN" "$chain_file"
{ cat "$certificate_file"; cat "$chain_file"; } > "$fullchain_file"

openssl verify -purpose sslserver -CAfile "$ROOT_CERT" -untrusted "$chain_file" "$certificate_file"
openssl x509 -in "$certificate_file" -noout -checkhost "${DNS_NAMES[0]}"

fingerprint=$(openssl x509 -in "$certificate_file" -noout -fingerprint -sha256 | cut -d= -f2)
not_after=$(openssl x509 -in "$certificate_file" -noout -enddate | cut -d= -f2-)
{
  printf 'name=%s\n' "$NAME"
  printf 'subject=%s\n' "$(openssl x509 -in "$certificate_file" -noout -subject | cut -d= -f2-)"
  printf 'sha256_fingerprint=%s\n' "$fingerprint"
  printf 'not_after=%s\n' "$not_after"
  printf 'dns_sans=%s\n' "$(IFS=,; printf '%s' "${DNS_NAMES[*]}")"
  printf 'ip_sans=%s\n' "$(IFS=,; printf '%s' "${IP_ADDRESSES[*]}")"
} > "$manifest_file"

rm -f -- "$csr_file" "$config_file"
chown -R "$SUDO_UID:$SUDO_GID" -- "$OUTPUT_DIR"
trap - ERR

printf 'Certificate generated in: %s\n' "$OUTPUT_DIR"
printf 'Certificate SHA-256 fingerprint: %s\n' "$fingerprint"
