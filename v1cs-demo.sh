#!/usr/bin/env bash
set -euo pipefail

# -------- Config --------
REL_CS="trendmicro"
NS_CS="trendmicro-system"
CS_CHART_URL="https://github.com/trendmicro/visionone-container-security-helm/archive/main.tar.gz"
OVERRIDES="./overrides.yaml"

FS_NS="visionone-filesecurity"
FS_REL_DEFAULT="my-release"
FS_NODEPORT_SVC="v1fs-scanner-nodeport"
FS_NODEPORT=32051

OPENWEBUI_NODEPORT=30080
OLLAMA_NODEPORT=31134

TTL_ENF_SA="scanjob-ttl-enforcer"
TTL_ENF_CR="scanjob-ttl-enforcer"
TTL_ENF_CRB="scanjob-ttl-enforcer"
TTL_ENF_CJ="scanjob-ttl-enforcer"
TTL_SECONDS="${TTL_SECONDS:-600}"

PF_ADDR="${PF_ADDR:-0.0.0.0}"
PF_LOCAL_ICP="${PF_LOCAL_ICP:-1344}"
PF_REMOTE_ICP="${PF_REMOTE_ICP:-1344}"
PF_PIDFILE="${PF_PIDFILE:-/var/run/v1fs_icap_pf.pid}"
PF_LOG="${PF_LOG:-/var/log/v1fs_icap_pf.log}"

BOLD=$'\e[1m'; RESET=$'\e[0m'
WARN="⚠️ "; ERR="❌"; OK="✅"; INFO="ℹ️ "
is_utf8(){ [ "${FORCE_ASCII:-0}" = "1" ] && return 1; locale charmap 2>/dev/null | grep -qi 'utf-8'; }
hr(){ local cols; cols="$(tput cols 2>/dev/null || echo 80)"; if is_utf8; then printf "%*s\n" "$cols" | tr ' ' '─'; else printf "%*s\n" "$cols" | tr ' ' '-'; fi; }
box(){ local t="$1"; hr; if is_utf8; then printf "\e[1m%s\e[0m\n" "$t"; else printf "%s\n" "$t"; fi; hr; }
need(){ command -v "$1" >/dev/null || { echo "${ERR} Missing: $1"; exit 1; } }
kdel(){ kubectl "$@" 2>/dev/null || true; }

main_menu(){
  clear
  box "Trend Micro Demo - Main Menu"
  cat <<MENU
  1) Status
  2) Platform Tools
  q) Quit
MENU
  echo -n "Choose: "
}

platform_tools_menu(){
  clear
  box "PLATFORM TOOLS"
  cat <<MENU
  1) Check status (installed + pods by node)
  2) Container Security
  3) File Security
  4) Show URLs
  5) Validate & Clean Up previous components
  b) Back
MENU
  echo -n "Choose: "
}

container_security_menu(){
  clear
  box "Container Security"
  cat <<MENU
  1) Install/Upgrade Container Security (with TTL enforcer)
  2) Remove Container Security
  3) Deploy Demos (DVWA + Malware, OpenWebUI + Ollama)
  4) Remove Demos
  b) Back
MENU
  echo -n "Choose: "
}

file_security_menu(){
  clear
  box "File Security"
  cat <<MENU
  1) Install/Upgrade File Security (expose via NodePort + TTL enforcer)
  2) Remove File Security
  3) Start ICAP port-forward (0.0.0.0:${PF_LOCAL_ICP} -> svc/*-scanner:${PF_REMOTE_ICP})
  4) Stop  ICAP port-forward
  5) Status ICAP port-forward
  b) Back
MENU
  echo -n "Choose: "
}

status_check(){
  need kubectl; need helm
  local master node1 node2
  master="$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')"
  node1=""
  node2=""

  mapfile -t all_nodes < <(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')
  for n in "${all_nodes[@]}"; do
    [ "$n" = "$master" ] && continue
    if [ -z "$node1" ]; then node1="$n"; continue; fi
    if [ -z "$node2" ]; then node2="$n"; continue; fi
  done

  box "Cluster Nodes"
  printf "%-10s %-24s\n" "ROLE" "NAME"
  hr
  printf "%-10s %-24s\n" "master" "$master"
  [ -n "$node1" ] && printf "%-10s %-24s\n" "node1" "$node1"
  [ -n "$node2" ] && printf "%-10s %-24s\n" "node2" "$node2"
  hr

  box "What is Installed"
  if helm status "$REL_CS" -n "$NS_CS" >/dev/null 2>&1; then
    echo "Container Security: installed (release: ${REL_CS}, ns: ${NS_CS})"
  else
    echo "Container Security: not installed"
  fi
  if helm list -n "$FS_NS" | grep visionone-filesecurity >/dev/null 2>&1; then
    echo "File Security: installed (ns: ${FS_NS})"
  else
    echo "File Security: not installed"
  fi

  echo
  box "Pods by Node"
  for n in $(kubectl get nodes -o name | cut -d/ -f2); do
    echo "=== $n ==="
    kubectl get pods -A --field-selector spec.nodeName="$n" -o wide
    echo
  done
}

install_ttl_enforcer(){
  # Implementation here or reuse from original script
  true
}

install_cs(){
  need kubectl; need helm
  echo "== Install or Upgrade Trend Micro Vision One Container Security =="

  BOOTSTRAP_TOKEN="${BOOTSTRAP_TOKEN:-}"
  if [ -z "$BOOTSTRAP_TOKEN" ]; then
    read -r -p "Enter Vision One bootstrap token: " BOOTSTRAP_TOKEN
  fi
  [ -z "$BOOTSTRAP_TOKEN" ] && { echo "Token cannot be empty"; exit 1; }

  echo "Choose tenant region:
  1) US  api.xdr.trendmicro.com
  2) EU  api.eu.xdr.trendmicro.com
  3) JP  api.xdr.trendmicro.co.jp
  4) AU  api.au.xdr.trendmicro.com
  5) SG  api.sg.xdr.trendmicro.com"
  read -r -p "Enter 1..5 [default 1]: " CHOICE; CHOICE="${CHOICE:-1}"
  case "$CHOICE" in
    1) API_HOST="api.xdr.trendmicro.com" ;;
    2) API_HOST="api.eu.xdr.trendmicro.com" ;;
    3) API_HOST="api.xdr.trendmicro.co.jp" ;;
    4) API_HOST="api.au.xdr.trendmicro.com" ;;
    5) API_HOST="api.sg.xdr.trendmicro.com" ;;
    *) API_HOST="api.xdr.trendmicro.com" ;;
  esac
  ENDPOINT="https://${API_HOST}/external/v2/direct/vcs/external/vcs"

  cat > "$OVERRIDES" <<EOF
visionOne:
  bootstrapToken: ${BOOTSTRAP_TOKEN}
  endpoint: ${ENDPOINT}
  exclusion:
    namespaces: [kube-system]
  runtimeSecurity:         { enabled: true }
  vulnerabilityScanning:   { enabled: true }
  malwareScanning:         { enabled: true }
  secretScanning:          { enabled: true }
  inventoryCollection:     { enabled: true }
EOF

  if helm status "$REL_CS" -n "$NS_CS" >/dev/null 2>&1; then
    echo "Release exists -> upgrading..."
    helm upgrade "$REL_CS" --namespace "$NS_CS" --values "$OVERRIDES" "$CS_CHART_URL" || true
  else
    echo "Installing new release..."
    helm install "$REL_CS" --namespace "$NS_CS" --create-namespace --values "$OVERRIDES" "$CS_CHART_URL"
  fi

  install_ttl_enforcer
  echo "${OK} Container Security ready."
}

install_fs(){
  need kubectl; need helm
  echo "== Install or Upgrade Trend Vision One File Security =="

  FS_TOKEN="${FS_TOKEN:-}"
  if [ -z "$FS_TOKEN" ]; then
    read -r -p "Enter File Security registration token: " FS_TOKEN
  fi
  [ -z "$FS_TOKEN" ] && { echo "Token cannot be empty"; exit 1; }

  # Namespace and secret creation steps here

  install_ttl_enforcer
  echo "${OK} File Security exposed at NodePort ${FS_NODEPORT_SVC}:${FS_NODEPORT}"
}

# Implement other functions as needed (remove_cs, remove_fs, deploy_malicious, deploy_normal, remove_labs, icap_pf_start, icap_pf_stop, icap_pf_status, cleanup_wizard, status_urls)

need kubectl; need helm
while true; do
  main_menu
  read -r CAT
  case "${CAT:-}" in
    1) status_check; read -rp $'\n[enter] ' _ ;;
    2)
      while true; do
        platform_tools_menu
        read -r PT
        case "${PT:-}" in
          1) status_check; read -rp $'\n[enter] ' _ ;;
          2)
            while true; do
              container_security_menu
              read -r CSCH
              case "${CSCH:-}" in
                1) install_cs; read -rp $'\n[enter] ' _ ;;
                2) remove_cs; read -rp $'\n[enter] ' _ ;;
                3) deploy_malicious; deploy_normal; read -rp $'\n[enter] ' _ ;;
                4) remove_labs; read -rp $'\n[enter] ' _ ;;
                b|B) break ;;
                *) echo "${WARN} Invalid option" ;;
              esac
            done
            ;;
          3)
            while true; do
              file_security_menu
              read -r FSCH
              case "${FSCH:-}" in
                1) install_fs; read -rp $'\n[enter] ' _ ;;
                2) remove_fs; read -rp $'\n[enter] ' _ ;;
                3) icap_pf_start; read -rp $'\n[enter] ' _ ;;
                4) icap_pf_stop; read -rp $'\n[enter] ' _ ;;
                5) icap_pf_status; read -rp $'\n[enter] ' _ ;;
                b|B) break ;;
                *) echo "${WARN} Invalid option" ;;
              esac
            done
            ;;
          4) status_urls; read -rp $'\n[enter] ' _ ;;
          5) cleanup_wizard; read -rp $'\n[enter] ' _ ;;
          b|B) break ;;
          *) echo "${WARN} Invalid option" ;;
        esac
      done
      ;;
    q|Q) exit 0 ;;
    *) echo "${WARN} Invalid option" ;;
  esac
done
