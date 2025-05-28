#!/bin/bash
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-mlops-test-cluster}"
CONTEXT="kind-${CLUSTER_NAME}"

echo "🚀 Deploying ingress controller and HTTP services..."

# Deploy NGINX Ingress Controller
deploy_ingress_controller() {
    echo "📦 Deploying NGINX Ingress Controller..."
    
    kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml --context "$CONTEXT"
    
    echo "⏳ Waiting for ingress controller to be ready..."
    kubectl wait --namespace ingress-nginx \
        --for=condition=ready pod \
        --selector=app.kubernetes.io/component=controller \
        --timeout=300s --context "$CONTEXT"
    
    echo "✅ Ingress controller deployed successfully"
}

# Deploy HTTP echo services
deploy_echo_services() {
    echo "📦 Deploying foo and bar echo services..."
    
    # Deploy foo service with proper YAML manifest
    cat <<EOF | kubectl apply --context "$CONTEXT" -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: foo-echo
  labels:
    app: foo-echo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: foo-echo
  template:
    metadata:
      labels:
        app: foo-echo
    spec:
      containers:
      - name: echo
        image: hashicorp/http-echo:latest
        args:
        - "-text=foo"
        - "-listen=:8080"
        ports:
        - containerPort: 8080
        readinessProbe:
          httpGet:
            path: /
            port: 8080
          initialDelaySeconds: 10
          periodSeconds: 5
        livenessProbe:
          httpGet:
            path: /
            port: 8080
          initialDelaySeconds: 15
          periodSeconds: 10
---
apiVersion: v1
kind: Service
metadata:
  name: foo-service
spec:
  selector:
    app: foo-echo
  ports:
  - port: 80
    targetPort: 8080
EOF

    # Deploy bar service with proper YAML manifest
    cat <<EOF | kubectl apply --context "$CONTEXT" -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: bar-echo
  labels:
    app: bar-echo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: bar-echo
  template:
    metadata:
      labels:
        app: bar-echo
    spec:
      containers:
      - name: echo
        image: hashicorp/http-echo:latest
        args:
        - "-text=bar"
        - "-listen=:8080"
        ports:
        - containerPort: 8080
        readinessProbe:
          httpGet:
            path: /
            port: 8080
          initialDelaySeconds: 10
          periodSeconds: 5
        livenessProbe:
          httpGet:
            path: /
            port: 8080
          initialDelaySeconds: 15
          periodSeconds: 10
---
apiVersion: v1
kind: Service
metadata:
  name: bar-service
spec:
  selector:
    app: bar-echo
  ports:
  - port: 80
    targetPort: 8080
EOF
    
    echo "✅ Echo services deployed successfully"
}


# Create ingress routing
create_ingress_routes() {
    echo "🔗 Creating ingress routes..."
    
    cat <<EOF | kubectl apply --context "$CONTEXT" -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: echo-ingress
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  ingressClassName: nginx
  rules:
  - host: foo.localhost
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: foo-service
            port:
              number: 80
  - host: bar.localhost
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: bar-service
            port:
              number: 80
EOF
    
    echo "✅ Ingress routes created successfully"
}

# Wait for deployments to be ready
wait_for_deployments() {
    echo "⏳ Waiting for deployments to be ready..."
    
    kubectl wait --for=condition=available deployment/foo-echo --timeout=120s --context "$CONTEXT"
    kubectl wait --for=condition=available deployment/bar-echo --timeout=120s --context "$CONTEXT"
    
    # Additional wait for ingress to propagate
    echo "⏳ Waiting for ingress routes to propagate..."
    sleep 30
    
    echo "✅ All deployments are ready"
}

# Display deployment summary
display_deployment_summary() {
    echo ""
    echo "📊 Deployment Summary:"
    echo "====================="
    
    echo ""
    echo "🖥️ Deployments:"
    kubectl get deployments --context "$CONTEXT"
    
    echo ""
    echo "🔗 Services:"
    kubectl get services --context "$CONTEXT"
    
    echo ""
    echo "🌐 Ingress:"
    kubectl get ingress --context "$CONTEXT"
    
    echo ""
    echo "📊 HTTP Services Summary:"
    echo "========================"
    echo "🔗 foo service: http://foo.localhost"
    echo "🔗 bar service: http://bar.localhost"
    echo ""
    echo "🎯 Next step: Run ./test-ingress.sh to validate HTTP connectivity"
}

# Main execution
main() {
    # Verify cluster exists
    if ! kubectl cluster-info --context "$CONTEXT" &>/dev/null; then
        echo "❌ Cluster $CLUSTER_NAME not found or not accessible"
        echo "🔍 Run ./provision-cluster.sh first"
        exit 1
    fi
    
    deploy_ingress_controller
    deploy_echo_services
    create_ingress_routes
    wait_for_deployments
    display_deployment_summary
    
    echo "🎉 Ingress deployment completed successfully!"
}

main "$@"

