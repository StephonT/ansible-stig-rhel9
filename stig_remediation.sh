#!/usr/bin/env bash
# =============================================================================
# run_stig_remediation.sh
# Runs ansible-playbook with one or more DISA-STIG-RHEL-09-* tags
# =============================================================================

set -euo pipefail

PLAYBOOK="playbooks/remediate.yml"
INVENTORY="inventory/stig_hosts.yml"
LIMIT="ipaclient1"
TAG_PREFIX="DISA-STIG-RHEL-09-"

# ---------- helpers -----------------------------------------------------------

print_banner() {
  echo ""
  echo "============================================="
  echo "   DISA STIG RHEL 9 Remediation Runner"
  echo "============================================="
  echo ""
}

validate_stig_number() {
  local num="$1"
  # STIG numbers are typically 6-digit zero-padded integers (e.g. 010010)
  if [[ ! "$num" =~ ^[0-9]{1,10}$ ]]; then
    echo "  [ERROR] '$num' is not a valid STIG number. Only digits are allowed." >&2
    return 1
  fi
  return 0
}

build_tags() {
  local numbers=("$@")
  local tags=""
  for num in "${numbers[@]}"; do
    [[ -n "$tags" ]] && tags+=","
    tags+="${TAG_PREFIX}${num}"
  done
  echo "$tags"
}

confirm_and_run() {
  local tags="$1"
  echo ""
  echo "  Playbook : $PLAYBOOK"
  echo "  Inventory: $INVENTORY"
  echo "  Limit    : $LIMIT"
  echo "  Tags     : $tags"
  echo ""
  read -rp "Proceed? [y/N]: " confirm
  case "$confirm" in
    [yY][eE][sS]|[yY])
      echo ""
      ansible-playbook "$PLAYBOOK" \
        --limit "$LIMIT" \
        -i "$INVENTORY" \
        --tags "$tags"
      echo ""
      echo "  [DONE] Remediation complete."
      ;;
    *)
      echo "  Aborted."
      exit 0
      ;;
  esac
}

# ---------- main --------------------------------------------------------------

print_banner

read -rp "Will you be using multiple STIG tags? [y/N]: " multi_answer

case "$multi_answer" in
  [yY][eE][sS]|[yY])
    echo ""
    echo "Enter STIG numbers one per line."
    echo "When finished, enter an empty line or press Ctrl+D."
    echo ""

    stig_numbers=()
    while true; do
      read -rp "  STIG number (or leave blank to finish): " input || break
      [[ -z "$input" ]] && break

      if validate_stig_number "$input"; then
        stig_numbers+=("$input")
        echo "  Added: ${TAG_PREFIX}${input}"
      fi
    done

    if [[ ${#stig_numbers[@]} -eq 0 ]]; then
      echo "  [ERROR] No valid STIG numbers entered. Exiting." >&2
      exit 1
    fi

    echo ""
    echo "  Tags queued (${#stig_numbers[@]}):"
    for n in "${stig_numbers[@]}"; do
      echo "    - ${TAG_PREFIX}${n}"
    done

    tags=$(build_tags "${stig_numbers[@]}")
    confirm_and_run "$tags"
    ;;

  *)
    echo ""
    read -rp "Enter the STIG number: " single_number

    if ! validate_stig_number "$single_number"; then
      exit 1
    fi

    tags="${TAG_PREFIX}${single_number}"
    confirm_and_run "$tags"
    ;;
esac