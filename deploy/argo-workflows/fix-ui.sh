#!/bin/bash

# Argo UI Troubleshooting Script
# Fixes common Argo Workflows UI access issues

echo "🔧 Fixing Argo Workflows UI access issues..."

# 1. Fix readiness probe configuration
echo "Step 1: Fixing readiness probe configuration..."
kubectl patch deployment argo-server -n argo -p '{
  "spec": {
    "template": {
      "spec": {
        "containers": [{
          "name": "argo-server",
          "readinessProbe": {
            "httpGet": {
              "scheme": "HTTP",
              "path": "/",
              "port": 2746
            }
          }
        }]
      }
    }
  }
}'

# 2. Wait for pod restart
echo "Step 2: Waiting for pod restart..."
kubectl rollout status deployment/argo-server -n argo --timeout=60s

# 3. Clean up existing port-forwards
echo "Step 3: Cleaning up existing port-forwards..."
pkill -f "kubectl port-forward.*argo-server" 2>/dev/null || true
pkill -f "kubectl port-forward.*2746" 2>/dev/null || true

# 4. Start new port-forward
echo "Step 4: Starting port-forward..."
kubectl port-forward --address 0.0.0.0 svc/argo-server 2746:2746 -n argo &
PF_PID=$!

# 5. Wait and test connection
echo "Step 5: Testing connection..."
sleep 5

if curl -s -f http://localhost:2746/api/v1/version >/dev/null 2>&1; then
    echo "✅ Success! Argo UI is now accessible!"
    echo "🌐 URL: http://localhost:2746"
    echo "🔄 Port-forward PID: $PF_PID"
    echo ""
    echo "💡 If issues occur again, run: ./fix-argo-ui.sh"
else
    echo "❌ Connection test failed, please check pod status"
    kubectl get pods -n argo -l app=argo-server
fi
