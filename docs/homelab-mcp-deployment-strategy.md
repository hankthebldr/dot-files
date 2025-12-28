# Homelab MCP Server Deployment Strategy
## MicroK8s Deployment on 192.168.1.104

**Target Environment:**
- Primary Server: 192.168.1.104 (MicroK8s + MCP Server)
- Secondary Server: 192.168.1.101 (Available for scaling)
- Username: henry
- Local Network: 192.168.1.0/24

---

## 🎯 Deployment Strategy Overview

### Architecture Design

```
┌─────────────────────────────────────────────────────────────┐
│                    Your MacBook Pro                         │
│              (192.168.1.x - MCP Client)                     │
│                                                             │
│  Claude Code / Claude Desktop / Custom MCP Clients          │
└──────────────────┬──────────────────────────────────────────┘
                   │
                   │ HTTPS/WSS
                   │ (192.168.1.104:443)
                   │
┌──────────────────▼──────────────────────────────────────────┐
│              192.168.1.104 - MicroK8s Cluster               │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              MetalLB Load Balancer                  │   │
│  │           (192.168.1.200-192.168.1.210)            │   │
│  └──────────────────┬──────────────────────────────────┘   │
│                     │                                       │
│  ┌──────────────────▼──────────────────────────────────┐   │
│  │            NGINX Ingress Controller                 │   │
│  │     (SSL/TLS Termination, Path Routing)            │   │
│  └──────────────────┬──────────────────────────────────┘   │
│                     │                                       │
│  ┌──────────────────▼──────────────────────────────────┐   │
│  │            MCP Server Deployment                    │   │
│  │                                                     │   │
│  │  ┌──────────────┐  ┌──────────────┐               │   │
│  │  │ MCP Server   │  │ MCP Server   │  (Auto-scale) │   │
│  │  │ Pod 1        │  │ Pod 2        │               │   │
│  │  │              │  │              │               │   │
│  │  │ - Resources  │  │ - Resources  │               │   │
│  │  │ - Tools      │  │ - Tools      │               │   │
│  │  │ - Prompts    │  │ - Prompts    │               │   │
│  │  └──────────────┘  └──────────────┘               │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              Persistent Storage                     │   │
│  │         (PVC for MCP server data)                   │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

---

## 📦 Component Selection

### MCP Server Implementation
**Language:** Python (Official SDK 1.2.0+)
- Mature SDK with full feature support
- Excellent for rapid development
- Easy integration with homelab services

**Transport:** Streamable HTTP with SSE
- Production-ready protocol (replaces deprecated stdio/SSE-only)
- Works with load balancers and proxies
- Supports both streaming and request/response patterns
- HTTPS-ready for secure communication

### MCP Server Capabilities

The server will expose:

1. **Resources** - Access to homelab data and files
   - File system access (controlled paths)
   - Configuration files
   - Log aggregation
   - Documentation

2. **Tools** - Executable functions
   - System monitoring (CPU, memory, disk, network)
   - Container management (Docker/K8s operations)
   - Network diagnostics (ping, traceroute, port scan)
   - Service health checks
   - File operations
   - Custom homelab automation

3. **Prompts** - Pre-configured workflows
   - Infrastructure status report
   - Security audit procedures
   - Backup verification
   - Service deployment templates

---

## 🚀 Deployment Phases

### Phase 1: Server Preparation (192.168.1.104)
1. Install/verify MicroK8s
2. Enable required add-ons (ingress, metallb, dns, storage)
3. Configure MetalLB IP pool (192.168.1.200-210)
4. Set up TLS certificates (self-signed or Let's Encrypt)

### Phase 2: MCP Server Development
1. Build Python MCP server with homelab-specific tools
2. Create Docker container image
3. Push to local registry or Docker Hub
4. Test locally before K8s deployment

### Phase 3: Kubernetes Deployment
1. Create namespace (mcp-system)
2. Deploy secrets (API keys, credentials)
3. Deploy MCP server with ConfigMaps
4. Create Service (ClusterIP)
5. Configure Ingress with TLS
6. Set up health checks and monitoring

### Phase 4: Client Configuration
1. Configure Claude Desktop MCP client
2. Set up Claude Code integration
3. Test connectivity and functionality
4. Document custom tools and usage

### Phase 5: Scaling & Optimization
1. Configure horizontal pod autoscaling
2. Set up monitoring (Prometheus/Grafana)
3. Implement logging aggregation
4. Add backup/restore procedures

---

## 🔐 Security Considerations

### Network Security
- Use TLS/HTTPS for all communications
- Self-signed certificate for local network (or mDNS + Let's Encrypt)
- IP whitelist in Ingress (restrict to local network)
- Network policies to isolate MCP pods

### Authentication & Authorization
- API key authentication for MCP endpoints
- Kubernetes RBAC for service accounts
- Secret management for credentials
- Token-based access control

### Access Control
- MCP server limited to safe operations
- Filesystem access restricted to allowed paths
- Command execution sandboxed
- Rate limiting on expensive operations

---

## 🛠️ MicroK8s Configuration

### Required Add-ons
```bash
microk8s enable dns           # CoreDNS for service discovery
microk8s enable storage       # Persistent volume support
microk8s enable ingress       # NGINX Ingress Controller
microk8s enable metallb       # Load Balancer (192.168.1.200-210)
microk8s enable cert-manager  # Certificate management (optional)
microk8s enable registry      # Local container registry (optional)
microk8s enable prometheus    # Monitoring (optional)
```

### MetalLB IP Pool
Allocate IPs from your local network:
- Pool: 192.168.1.200 - 192.168.1.210
- MCP Service will get one IP (e.g., 192.168.1.200)

### Ingress Configuration
- Host: mcp.homelab.local (add to /etc/hosts)
- Path: /mcp (MCP endpoint)
- Path: /health (Health check)
- TLS: Enabled with self-signed cert

---

## 📊 Resource Allocation

### MCP Server Pod
```yaml
resources:
  requests:
    cpu: 250m
    memory: 512Mi
  limits:
    cpu: 1000m
    memory: 2Gi
```

### Scaling Configuration
- Min replicas: 1
- Max replicas: 3
- Target CPU: 70%
- Target Memory: 80%

---

## 🔄 Deployment Workflow

### Automated Deployment Process

1. **SSH to homelab server** (192.168.1.104)
2. **Run setup script** to install/configure MicroK8s
3. **Build MCP server Docker image**
4. **Apply Kubernetes manifests**
5. **Verify deployment** with health checks
6. **Configure macOS client** with connection details
7. **Test MCP functionality**

### Update Workflow

1. Update MCP server code
2. Build new Docker image with version tag
3. Apply Kubernetes deployment update
4. Rolling update with zero downtime
5. Verify new version health

---

## 📁 File Structure

```
homelab-mcp/
├── mcp-server/
│   ├── src/
│   │   ├── __init__.py
│   │   ├── server.py           # Main MCP server
│   │   ├── tools/
│   │   │   ├── __init__.py
│   │   │   ├── system.py       # System monitoring tools
│   │   │   ├── containers.py   # Docker/K8s tools
│   │   │   ├── network.py      # Network diagnostic tools
│   │   │   └── files.py        # File operation tools
│   │   ├── resources/
│   │   │   ├── __init__.py
│   │   │   └── homelab.py      # Homelab resources
│   │   └── prompts/
│   │       ├── __init__.py
│   │       └── workflows.py    # Pre-configured prompts
│   ├── Dockerfile
│   ├── requirements.txt
│   └── config.yaml
├── kubernetes/
│   ├── namespace.yaml
│   ├── secrets.yaml
│   ├── configmap.yaml
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── ingress.yaml
│   ├── pvc.yaml
│   └── hpa.yaml
├── scripts/
│   ├── setup-microk8s.sh       # Server setup
│   ├── build-and-push.sh       # Docker build
│   ├── deploy.sh               # K8s deployment
│   ├── update.sh               # Rolling update
│   └── rollback.sh             # Rollback deployment
├── client/
│   ├── claude-desktop-config.json
│   └── test-connection.py
└── docs/
    ├── deployment-guide.md
    ├── api-reference.md
    └── troubleshooting.md
```

---

## 🎯 Success Criteria

### Deployment Success
- [ ] MicroK8s running on 192.168.1.104
- [ ] MCP server pods healthy and responding
- [ ] Ingress routing to MCP server
- [ ] TLS/HTTPS working
- [ ] Health checks passing

### Functionality Success
- [ ] MCP client can connect from macOS
- [ ] Resources accessible (files, configs)
- [ ] Tools executable (system monitoring, etc.)
- [ ] Prompts working
- [ ] Performance acceptable (<200ms response time)

### Security Success
- [ ] HTTPS-only communication
- [ ] Authentication required
- [ ] No unauthorized access
- [ ] Secrets properly managed
- [ ] Audit logging enabled

---

## 🔧 Maintenance & Monitoring

### Health Monitoring
- Kubernetes liveness/readiness probes
- Prometheus metrics (optional)
- Log aggregation to stdout
- External health check from macOS

### Backup Strategy
- ConfigMaps/Secrets backed up
- Persistent volume snapshots
- Docker images versioned and stored
- Kubernetes manifests in Git

### Update Strategy
- Rolling updates with health checks
- Canary deployments for major changes
- Quick rollback capability
- Version tagging for all releases

---

## 📚 Next Steps

1. Review and approve strategy
2. Execute setup-microk8s.sh on 192.168.1.104
3. Build and deploy MCP server
4. Configure client on macOS
5. Test and iterate
6. Add custom tools for your homelab
7. Scale to 192.168.1.101 if needed

---

**Created**: 2025-11-06
**Target Server**: 192.168.1.104 (henry@homelab)
**Client**: MacBook Pro (macOS 26.1)
**Network**: 192.168.1.0/24 (Private Homelab)
