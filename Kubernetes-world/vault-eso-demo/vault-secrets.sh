#!/usr/bin/env bash
set -euo pipefail

VAULT_NAMESPACE="${VAULT_NAMESPACE:-vault}"
VAULT_ROOT_TOKEN="${VAULT_ROOT_TOKEN:-root}"
SECRET_PATH="secret/demo"

vault_cli() {
  kubectl -n "${VAULT_NAMESPACE}" exec vault-0 -- \
    env VAULT_ADDR=http://127.0.0.1:8765 \
    VAULT_TOKEN="${VAULT_ROOT_TOKEN}" \
    vault "$@"
}

usage() {
  cat <<EOF
Usage:
  $0 create [username] [password]
  $0 update [username] [password]
  $0 get
  $0 delete

Examples:
  $0 create demo-user first-password
  $0 update updated-user new-password
  $0 get
  $0 delete
EOF
}

action="${1:-}"

case "${action}" in
  create)
    username="${2:-demo-user}"
    password="${3:-super-secret-password}"

    if vault_cli kv get "${SECRET_PATH}" >/dev/null 2>&1; then
      echo "ERROR: ${SECRET_PATH} already exists. Use '$0 update'."
      exit 1
    fi

    vault_cli kv put -cas=0 "${SECRET_PATH}" \
      username="${username}" \
      password="${password}"
    echo "Created ${SECRET_PATH}."
    ;;

  update)
    username="${2:-updated-user}"
    password="${3:-new-password}"

    if ! vault_cli kv get "${SECRET_PATH}" >/dev/null 2>&1; then
      echo "ERROR: ${SECRET_PATH} does not exist. Use '$0 create'."
      exit 1
    fi

    vault_cli kv put "${SECRET_PATH}" \
      username="${username}" \
      password="${password}"
    echo "Updated ${SECRET_PATH}. ESO will synchronize it within 15 seconds."
    ;;

  get)
    vault_cli kv get "${SECRET_PATH}"
    ;;

  delete)
    vault_cli kv metadata delete "${SECRET_PATH}"
    echo "Permanently deleted ${SECRET_PATH} and all of its versions."
    ;;

  *)
    usage
    exit 1
    ;;
esac
