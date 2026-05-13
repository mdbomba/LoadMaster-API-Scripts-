#!/usr/bin/env bash
set -euo pipefail

trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

prompt_required() {
  local prompt="$1"
  local value
  while true; do
    read -r -p "$prompt" value
    value="$(trim "$value")"
    if [[ -n "$value" ]]; then
      printf '%s' "$value"
      return 0
    fi
    echo "Value is required."
  done
}

prompt_optional_default() {
  local prompt="$1"
  local default_value="$2"
  local value
  read -r -p "$prompt" value
  value="$(trim "$value")"
  if [[ -z "$value" ]]; then
    printf '%s' "$default_value"
  else
    printf '%s' "$value"
  fi
}

prompt_yes_no() {
  local prompt="$1"
  local default_value="$2"
  local value
  while true; do
    read -r -p "$prompt" value
    value="$(trim "$value")"
    if [[ -z "$value" ]]; then
      value="$default_value"
    fi
    case "${value,,}" in
      y|yes) printf '1'; return 0 ;;
      n|no) printf '0'; return 0 ;;
      *) echo "Please answer y or n." ;;
    esac
  done
}

url_encode() {
  python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$1"
}

extract_first_number() {
  local input="$1"
  local n
  n=$(printf '%s' "$input" | grep -Eo '[0-9]+' | head -n1 || true)
  printf '%s' "$n"
}

api_call() {
  local endpoint="$1"
  shift
  local query
  query=$(IFS='&'; echo "$*")

  local url="https://${LM_HOST}/access/${endpoint}"
  if [[ -n "$query" ]]; then
    url="${url}?${query}"
  fi

  if [[ "$SKIP_TLS_VERIFY" == "1" ]]; then
    curl -ksS --fail -u "${LM_USER}:${LM_PASS}" "$url"
  else
    curl -sS --fail -u "${LM_USER}:${LM_PASS}" "$url"
  fi
}

resolve_id() {
  local id_from_response="$1"
  local prompt="$2"
  if [[ -n "$id_from_response" ]]; then
    printf '%s' "$id_from_response"
    return 0
  fi
  prompt_required "$prompt"
}

echo "LoadMaster Virtual Service + 2 SubVS automation"
echo

LM_HOST=$(prompt_required "LoadMaster host/IP: ")
LM_USER=$(prompt_required "API username: ")
read -r -s -p "API password: " LM_PASS
echo
SKIP_TLS_VERIFY=$(prompt_yes_no "Skip TLS certificate verification? [y/N]: " "n")

echo
VS_NAME=$(prompt_required "Virtual Service nickname: ")
VS_IP=$(prompt_required "Virtual Service IP address: ")
VS_PORT=$(prompt_required "Virtual Service port: ")
VS_PROTOCOL=$(prompt_optional_default "Virtual Service protocol [tcp]: " "tcp")

echo "Select VS type:"
echo "  1) L7 non-transparent"
echo "  2) L7 transparent"
echo "  3) L4"
while true; do
  VS_TYPE_OPTION=$(prompt_required "Choice [1-3]: ")
  case "$VS_TYPE_OPTION" in
    1) VS_TYPE_VALUE="http"; break ;;
    2) VS_TYPE_VALUE="http-transparent"; break ;;
    3) VS_TYPE_VALUE="gen"; break ;;
    *) echo "Invalid choice." ;;
  esac
done

SSL_ACCEL=$(prompt_yes_no "Enable SSL acceleration? [y/N]: " "n")
SSL_REENCRYPT=$(prompt_yes_no "Enable SSL re-encryption? [y/N]: " "n")
SUBNET_ORIGINATING=$(prompt_yes_no "Enable Subnet Originating Request? [y/N]: " "n")
ENABLE_WAF=$(prompt_yes_no "Enable WAF? [y/N]: " "n")
ENABLE_ESP=$(prompt_yes_no "Enable ESP? [y/N]: " "n")
ENABLE_CONTENT_RULES=$(prompt_yes_no "Enable content rules on the parent VS? [Y/n]: " "y")

if [[ "$SSL_ACCEL" == "1" ]]; then
  CERT_NAME=$(prompt_required "Certificate name for SSL acceleration: ")
else
  CERT_NAME=""
fi

echo
SUBVS1_NAME=$(prompt_required "SubVS #1 nickname: ")
SUBVS1_HOST=$(prompt_required "SubVS #1 host-header match (e.g. app1.example.com): ")
SUBVS1_RULE=$(prompt_optional_default "SubVS #1 content rule name [host_rule_1]: " "host_rule_1")

echo
SUBVS2_NAME=$(prompt_required "SubVS #2 nickname: ")
SUBVS2_HOST=$(prompt_required "SubVS #2 host-header match (e.g. app2.example.com): ")
SUBVS2_RULE=$(prompt_optional_default "SubVS #2 content rule name [host_rule_2]: " "host_rule_2")

echo
printf 'Creating parent VS...\n'
VS_RESPONSE=$(api_call "addvs" \
  "address=$(url_encode "$VS_IP")" \
  "port=$(url_encode "$VS_PORT")" \
  "prot=$(url_encode "$VS_PROTOCOL")" \
  "name=$(url_encode "$VS_NAME")" \
  "vstype=$(url_encode "$VS_TYPE_VALUE")")
echo "$VS_RESPONSE"

VS_ID=$(extract_first_number "$VS_RESPONSE")
VS_ID=$(resolve_id "$VS_ID" "Unable to auto-detect VS ID. Enter VS ID: ")

printf 'Applying parent VS options...\n'
VS_OPTS=(
  "index=$(url_encode "$VS_ID")"
  "sslaccel=$(url_encode "$SSL_ACCEL")"
  "sslreencrypt=$(url_encode "$SSL_REENCRYPT")"
  "subnetoriginating=$(url_encode "$SUBNET_ORIGINATING")"
  "waf=$(url_encode "$ENABLE_WAF")"
  "esp=$(url_encode "$ENABLE_ESP")"
  "enablecontentrules=$(url_encode "$ENABLE_CONTENT_RULES")"
)
if [[ -n "$CERT_NAME" ]]; then
  VS_OPTS+=("cert=$(url_encode "$CERT_NAME")")
fi
VS_MOD_RESPONSE=$(api_call "modifyvs" "${VS_OPTS[@]}")
echo "$VS_MOD_RESPONSE"

printf 'Creating SubVS #1...\n'
SUBVS1_RESPONSE=$(api_call "addsubvs" \
  "id=$(url_encode "$VS_ID")" \
  "name=$(url_encode "$SUBVS1_NAME")")
echo "$SUBVS1_RESPONSE"
SUBVS1_ID=$(extract_first_number "$SUBVS1_RESPONSE")
SUBVS1_ID=$(resolve_id "$SUBVS1_ID" "Unable to auto-detect SubVS #1 ID. Enter SubVS #1 ID: ")

printf 'Creating SubVS #2...\n'
SUBVS2_RESPONSE=$(api_call "addsubvs" \
  "id=$(url_encode "$VS_ID")" \
  "name=$(url_encode "$SUBVS2_NAME")")
echo "$SUBVS2_RESPONSE"
SUBVS2_ID=$(extract_first_number "$SUBVS2_RESPONSE")
SUBVS2_ID=$(resolve_id "$SUBVS2_ID" "Unable to auto-detect SubVS #2 ID. Enter SubVS #2 ID: ")

printf 'Applying SubVS options...\n'
api_call "modifysubvs" \
  "id=$(url_encode "$SUBVS1_ID")" \
  "waf=$(url_encode "$ENABLE_WAF")" \
  "esp=$(url_encode "$ENABLE_ESP")" >/dev/null
api_call "modifysubvs" \
  "id=$(url_encode "$SUBVS2_ID")" \
  "waf=$(url_encode "$ENABLE_WAF")" \
  "esp=$(url_encode "$ENABLE_ESP")" >/dev/null

echo "Creating and assigning host-header content rules..."
RULE1_RESPONSE=$(api_call "addrule" \
  "vs=$(url_encode "$VS_ID")" \
  "prot=http" \
  "name=$(url_encode "$SUBVS1_RULE")" \
  "header=Host" \
  "match=$(url_encode "$SUBVS1_HOST")" \
  "action=Forward To" \
  "subvsid=$(url_encode "$SUBVS1_ID")")
echo "$RULE1_RESPONSE"

RULE2_RESPONSE=$(api_call "addrule" \
  "vs=$(url_encode "$VS_ID")" \
  "prot=http" \
  "name=$(url_encode "$SUBVS2_RULE")" \
  "header=Host" \
  "match=$(url_encode "$SUBVS2_HOST")" \
  "action=Forward To" \
  "subvsid=$(url_encode "$SUBVS2_ID")")
echo "$RULE2_RESPONSE"

echo
printf 'Completed. VS ID: %s | SubVS IDs: %s, %s\n' "$VS_ID" "$SUBVS1_ID" "$SUBVS2_ID"
