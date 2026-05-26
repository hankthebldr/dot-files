# Quick Commands Reference - Homelab Command Center

## 🚀 Most Useful Commands for Your Workflow

### Kubernetes Management
```bash
k9                      # Launch K9s TUI (best way to manage K8s!)
kgp                     # kubectl get pods
kgs                     # kubectl get services  
kgd                     # kubectl get deployments
kx                      # Switch Kubernetes context
kns                     # Switch Kubernetes namespace
klogs <pod-name>        # Multi-pod log tailing with stern
kwatch                  # Watch pods update in real-time
```

### Docker & Containers
```bash
lzd                     # Launch LazyDocker TUI (best way!)
dps                     # Docker ps (list containers)
di                      # Docker images
dex <container> bash    # Docker exec -it (jump into container)
dlog <container>        # Docker logs -f
dcleanup                # Clean up all Docker resources
```

### System Monitoring
```bash
btop                    # Beautiful system monitor (replaces top/htop)
procs                   # Modern process viewer (replaces ps)
duf                     # Modern disk usage (replaces df)
dust                    # Directory disk usage (replaces du)
diskusage               # Interactive disk usage analyzer (ncdu)
```

### Security Scanning
```bash
trivy-image nginx:latest              # Scan container image
trivy-fs                              # Scan current directory
grype-image myapp:latest              # Alternative scanner
```

### Git Workflows
```bash
glg                     # LazyGit TUI (amazing Git interface!)
glog                    # Pretty git log graph
gcm "message"           # Quick commit
gcpush "message"        # Commit and push
```

### Network & API Testing
```bash
myip                    # Show your public IP
localip                 # Show your local IP
ports                   # Show all listening ports
http api.example.com    # HTTPie - beautiful HTTP requests
pingtest                # Test connectivity to common hosts
portscan <ip>           # Quick nmap scan
```

### Data Processing
```bash
yq .                    # Pretty print YAML
jq .                    # Pretty print JSON
```

### Quick Help
```bash
help <command>          # Quick help via tldr
cheat                   # Interactive cheatsheets (navi)
cheet kubectl           # Cheat.sh with syntax highlighting
```

### File Operations
```bash
ls                      # Modern ls with icons (eza)
ll                      # Detailed list
la                      # List all including hidden
lt                      # Tree view (2 levels)
tree                    # Full tree view
```

### Terraform
```bash
tf                      # terraform
tfi                     # terraform init
tfp                     # terraform plan
tfa                     # terraform apply
```

### Cloud Providers
```bash
awswho                  # Show current AWS identity
awsprofile              # Switch AWS profile (with fzf)
gcpwho                  # Show GCP account
gcpproj                 # Show GCP project
```

---

## 💡 Pro Tips

1. **Try the TUIs first** - k9, lzd, glg, btop are game-changers
2. **Use tab completion** - Most commands have great completion
3. **Check the welcome banner** - It shows on every terminal start
4. **Customize further** - Edit `~/Github/Github_desktop/dot-files/aliases.zsh`

---

## 🔄 To Apply Changes

After modifying your config:
```bash
source ~/.zshrc
```

## 📊 Currently Installed (15/16 tools)

✅ k9s, kubectx, kubens, stern, kustomize
✅ ansible, trivy, grype, age, sops
✅ yq, httpie, ncdu, watch, entr

❌ packer (not available via brew - use official install if needed)

---

**Generated:** $(date)
**Location:** ~/quick-commands-reference.md
