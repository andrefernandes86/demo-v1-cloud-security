# Trend Vision One (Container/File Security) Lab Helper

Turn a Kubernetes cluster into a hands-on demo/lab for **Trend Micro Vision One**.  
This script installs and manages:

- **Vision One Container Security** (via Helm)
- **Vision One File Security** (scanner)
- Demo workloads: **DVWA**, **Malware Samples**, **OpenWebUI + Ollama**
- Utilities: TTL job cleanup, URL board, ICAP port-forward, and a cleanup wizard

It’s a **menu-driven** Bash tool — no YAML editing required.

---

## Requirements

- **Kubernetes**: v1.24+ (tested with v1.30)
- **Kubectl & Helm 3** installed and configured for your cluster
- Cluster-admin permissions
- **Outbound internet** (pull container images & Helm charts)
- **Vision One account** with:
  - **Container Security** bootstrap token
  - **File Security** registration token
- NodePorts allowed (default K8s range `30000–32767`)
- Optional but useful: 2+ nodes (demos pin some services)

> ⚠️ The **DVWA** and **Malware Samples** pods are for demo/testing. They’re containerized and isolated, but still handle intentionally vulnerable content. Use only in non-production lab clusters.

---

## Download & Run

```bash
# From your repo
git clone https://github.com/andrefernandes86/demo-v1-cloud-security.git
cd demo-v1-cloud-security

# Or download just the script from this release
curl -fsSL -o v1cs-setup.sh https://raw.githubusercontent.com/andrefernandes86/demo-v1-cloud-security/main/v1cs-setup.sh
chmod +x v1cs-setup.sh

# Run (needs kubectl + helm configured)
sudo ./v1cs-setup.sh
```

You’ll see:

```
Trend Micro Demo - Main Menu
  1) Status
  2) Platform Tools
  q) Quit
Choose:
```

### 1) Status
- Shows nodes, what’s installed, and pods per node.

### 2) Platform Tools → (sub-menu)
```
PLATFORM TOOLS
  1) Check status (installed + pods by node)
  2) Container Security
  3) File Security
  4) Show URLs
  5) Validate & Clean Up previous components
  b) Back
```

#### Container Security → (sub-menu)
```
  1) Install/Upgrade Container Security (with TTL enforcer)
  2) Remove Container Security
  3) Deploy Demos (DVWA + Malware, OpenWebUI + Ollama)
  4) Remove Demos
  b) Back
```

- **Install/Upgrade**: you’ll be prompted for the **bootstrap token** and region.
- **Deploy Demos**: installs DVWA, Malware Samples (hostPorts on a worker), OpenWebUI+Ollama (NodePorts). Note: This step can take some time (up to 5 minutes).

#### File Security → (sub-menu)
```
  1) Install/Upgrade File Security (expose via NodePort + TTL enforcer)
  2) Remove File Security
  3) Start ICAP port-forward (0.0.0.0:1344 -> svc/*-scanner:1344)
  4) Stop  ICAP port-forward
  5) Status ICAP port-forward
  b) Back
```

- **Install/Upgrade**: you’ll be prompted for the **registration token**.
- **ICAP port-forward**: exposes the **scanner’s ICAP** on the node where you run the script (default **0.0.0.0:1344**).

#### Show URLs
Prints handy access URLs (DVWA, Malware Samples, OpenWebUI, Ollama API, and the File Security gRPC NodePort).

#### Validate & Clean Up previous components (Wizard)
Interactive cleanup for:
- Demo Deployments/Services (DVWA, Malware, OpenWebUI, Ollama)
- ICAP port-forward process
- OpenWebUI secret
- Trend Micro **scan-jobs** (forces TTL → fast GC)
- TTL enforcer (CronJob/SA/CR/CRB)
- Trend namespaces (if empty)
- CrashLoop / ImagePullBackOff pods

Choose “clean all” for a one-shot sweep, or pick items individually.

---

## Credentials You’ll Need

- **Vision One Container Security**:
  - **Bootstrap token** (prompted during install)
  - Tenant **region** (US/EU/JP/AU/SG)
- **Vision One File Security**:
  - **Registration token** (prompted during install)

Tokens are **not** stored by the script; they’re only written into a local `./overrides.yaml` Helm values file for the CS install step.

---

## Networking & Ports

- **OpenWebUI**: NodePort `30080` (HTTP)
- **Ollama**: NodePort `31134` (`/api/version`, models, etc.)
- **DVWA**: hostPort `8080` on a worker node
- **Malware Samples**: hostPort `8081` on a worker node
- **File Security scanner (gRPC)**: NodePort `32051` (for reference)
- **File Security scanner (ICAP)**: **not** exposed by default via NodePort.  
  Use the menu: **File Security → Start ICAP port-forward** → `0.0.0.0:1344 → svc/<release>-visionone-filesecurity-scanner:1344`

You can customize ICAP bind address/ports via env vars:
```bash
export TTL_SECONDS=600
export PF_ADDR=0.0.0.0
export PF_LOCAL_ICP=1344
export PF_REMOTE_ICP=1344
```

---

## Test the ICAP Service (simple web UI)

Run the test harness on any Docker host:
```bash
docker run -d --name v1fs-icap-server \
  -p 8080:8080 \
  --workdir /icap-scan-web \
  andrefernandes86/demo-v1fs-icap \
  python3 app.py
```
or

```
kubectl apply -f v1fs-icap-server.yaml
```

Open: `http://<docker-host>:8080/`

- Set **ICAP Host/IP** = the node where you started the port-forward
- Set **Port** = `1344` (or your `PF_LOCAL_ICP`)
- Click **Test Connection**
- Upload built-in **EICAR** or a **Normal file** to validate detection & clean flow

> This web app is static and requires **no API keys**. It only needs the ICAP host IP and port.

---

## Troubleshooting

- **OpenWebUI CrashLoopBackOff**: the script creates `openwebui-secret` with `WEBUI_SECRET_KEY` and sets `OLLAMA_BASE_URL=http://ollama:11434`. If you deployed it previously, run **Remove Demos** or the **Cleanup wizard**, then redeploy.
- **TTL enforcer ImagePullBackOff**: the CronJob uses `bitnami/kubectl:1.30`. If blocked, change the image in the script and re-run *Install/Upgrade*.
- **Port already in use (ICAP)**: change `PF_LOCAL_ICP` and start the port-forward again.
- **Leftovers**: use **Validate & Clean Up previous components**.

