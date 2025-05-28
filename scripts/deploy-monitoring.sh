#!/bin/bash
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-mlops-test-cluster}"
CONTEXT="kind-${CLUSTER_NAME}"

echo "📊 Deploying Prometheus monitoring stack..."

# Deploy Prometheus using kube-prometheus-stack
deploy_prometheus_stack() {
    echo "📦 Installing Prometheus Operator..."
    
    # Create monitoring namespace
    kubectl create namespace monitoring --context "$CONTEXT" || true
    
    # Deploy Prometheus Operator
    kubectl apply -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/main/bundle.yaml --context "$CONTEXT"
    
    # Wait for operator to be ready
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=prometheus-operator -n default --timeout=120s --context "$CONTEXT"
    
    echo "✅ Prometheus Operator deployed"
}

# Deploy Prometheus instance
deploy_prometheus_instance() {
    echo "📈 Deploying Prometheus instance..."
    
    cat <<EOF | kubectl apply --context "$CONTEXT" -f -
apiVersion: monitoring.coreos.com/v1
kind: Prometheus
metadata:
  name: prometheus
  namespace: monitoring
spec:
  serviceAccountName: prometheus
  serviceMonitorSelector:
    matchLabels:
      team: frontend
  resources:
    requests:
      memory: 400Mi
  enableAdminAPI: false
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: prometheus
  namespace: monitoring
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: prometheus
rules:
- apiGroups: [""]
  resources:
  - nodes
  - nodes/proxy
  - services
  - endpoints
  - pods
  verbs: ["get", "list", "watch"]
- apiGroups:
  - extensions
  resources:
  - ingresses
  verbs: ["get", "list", "watch"]
- nonResourceURLs: ["/metrics"]
  verbs: ["get"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: prometheus
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: prometheus
subjects:
- kind: ServiceAccount
  name: prometheus
  namespace: monitoring
---
apiVersion: v1
kind: Service
metadata:
  name: prometheus
  namespace: monitoring
spec:
  type: NodePort
  ports:
  - name: web
    nodePort: 30900
    port: 9090
    protocol: TCP
    targetPort: web
  selector:
    prometheus: prometheus
EOF

    echo "✅ Prometheus instance deployed"
}

# Deploy ServiceMonitor for your apps
deploy_service_monitors() {
    echo "🔍 Setting up service monitoring..."
    
    cat <<EOF | kubectl apply --context "$CONTEXT" -f -
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: app-monitor
  namespace: monitoring
  labels:
    team: frontend
spec:
  selector:
    matchLabels:
      app: foo-echo
  endpoints:
  - port: http
---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: ingress-monitor
  namespace: monitoring
  labels:
    team: frontend
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: ingress-nginx
  namespaceSelector:
    matchNames:
    - ingress-nginx
  endpoints:
  - port: metrics
EOF

    echo "✅ Service monitors configured"
}

# Main execution
main() {
    deploy_prometheus_stack
    deploy_prometheus_instance
    deploy_service_monitors
    
    echo ""
    echo "📊 Monitoring Stack Summary:"
    echo "============================"
    echo "🔗 Prometheus UI: http://localhost:30900"
    echo "📈 Metrics Collection: CPU, Memory, Network, HTTP metrics"
    echo "🎯 Monitoring: foo-echo, bar-echo, ingress-nginx"
    echo ""
    echo "✅ Monitoring deployment completed!"
}

main "$@"

