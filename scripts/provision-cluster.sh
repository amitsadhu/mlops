#!/bin/bash
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-mlops-test-cluster}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$(dirname "$SCRIPT_DIR")/config/kind-cluster.yaml"
NODE_READY_TIMEOUT="${NODE_READY_TIMEOUT:-300}"
MAX_RETRIES=3
RETRY_DELAY=10

echo "🚀 Starting Kubernetes cluster provisioning..."

# Enhanced function to wait for nodes to be ready
wait_for_nodes_ready() {
    local cluster_name=$1
    local expected_nodes=3
    local timeout=$NODE_READY_TIMEOUT
    local context="kind-${cluster_name}"
    
    echo "⏳ Waiting for all $expected_nodes nodes to be ready (timeout: ${timeout}s)..."
    
    # Give initial time for nodes to register
    echo "🔄 Initial wait for node registration..."
    sleep 45
    
    local start_time=$(date +%s)
    while true; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        
        if [[ $elapsed -gt $timeout ]]; then
            echo "❌ Timeout waiting for nodes to be ready"
            kubectl get nodes --context "$context" -o wide 2>/dev/null || true
            return 1
        fi
        
        # Get node status with better error handling
        local ready_nodes=0
        local total_nodes=0
        
        if kubectl get nodes --context "$context" --no-headers &>/dev/null; then
            ready_nodes=$(kubectl get nodes --context "$context" --no-headers 2>/dev/null | grep -c " Ready " || echo "0")
            total_nodes=$(kubectl get nodes --context "$context" --no-headers 2>/dev/null | wc -l || echo "0")
        else
            echo "⚠️ Cannot connect to cluster yet, retrying..."
            sleep 10
            continue
        fi
        
        echo "📊 Node status: $ready_nodes/$total_nodes ready (${elapsed}s elapsed)"
        
        if [[ "$ready_nodes" -eq "$expected_nodes" ]] && [[ "$total_nodes" -eq "$expected_nodes" ]]; then
            echo "✅ All $expected_nodes nodes are ready!"
            return 0
        fi
        
        sleep 15
    done
}

# Function to validate basic cluster health
validate_cluster_basic() {
    local cluster_name=$1
    local context="kind-${cluster_name}"
    
    echo "🏥 Starting basic cluster validation..."
    
    # 1. Cluster API connectivity
    echo "🔍 Validating cluster API connectivity..."
    if ! kubectl cluster-info --context "$context" &> /dev/null; then
        echo "❌ Cluster API validation failed"
        return 1
    fi
    echo "✅ Cluster API accessible"
    
    # 2. Node readiness verification
    echo "🔍 Validating node readiness..."
    local ready_nodes
    ready_nodes=$(kubectl get nodes --context "$context" --no-headers | grep -c " Ready " || echo "0")
    
    if [[ "$ready_nodes" -lt 3 ]]; then
        echo "❌ Expected 3 nodes, found $ready_nodes ready nodes"
        return 1
    fi
    echo "✅ All $ready_nodes nodes are ready"
    
    # 3. System pods validation
    echo "🔍 Validating system pods..."
    local system_pods_ready
    system_pods_ready=$(kubectl get pods -n kube-system --context "$context" --no-headers | grep -c " Running " || echo "0")
    local total_system_pods
    total_system_pods=$(kubectl get pods -n kube-system --context "$context" --no-headers | wc -l || echo "0")
    
    if [[ "$system_pods_ready" -lt "$total_system_pods" ]]; then
        echo "❌ System pods not ready: $system_pods_ready/$total_system_pods running"
        return 1
    fi
    echo "✅ All $system_pods_ready system pods are running"
    
    # 4. DNS functionality test
    echo "🔍 Validating DNS functionality..."
    if ! kubectl run dns-test --image=busybox --rm -i --restart=Never --context "$context" -- nslookup kubernetes.default.svc.cluster.local &>/dev/null; then
        echo "❌ DNS validation failed"
        return 1
    fi
    echo "✅ DNS functionality verified"
    
    echo "🎉 Basic cluster validation successful!"
    return 0
}

# Function to cleanup existing cluster
cleanup_cluster() {
    local cluster_name=$1
    echo "🧹 Cleaning up existing cluster: $cluster_name"
    
    if kind get clusters | grep -q "^${cluster_name}$"; then
        kind delete cluster --name "$cluster_name" || true
        sleep 5
    fi
}

# Function to provision cluster with progressive validation
provision_cluster() {
    local cluster_name=$1
    local config_file=$2
    local attempt=1
    
    while [[ $attempt -le $MAX_RETRIES ]]; do
        echo "🔄 Provisioning attempt $attempt/$MAX_RETRIES..."
        
        # Cleanup any existing cluster
        cleanup_cluster "$cluster_name"
        
        # Create new cluster
        if kind create cluster --name "$cluster_name" --config "$config_file" --wait 300s; then
            echo "✅ Cluster created successfully"
            
            # Progressive validation strategy
            echo "🔄 Starting progressive validation..."
            
            # Step 1: Wait for basic node readiness
            if wait_for_nodes_ready "$cluster_name"; then
                echo "✅ Node readiness validation passed"
                
                # Step 2: Basic cluster validation
                if validate_cluster_basic "$cluster_name"; then
                    echo "🎉 Cluster provisioning and validation completed successfully!"
                    return 0
                else
                    echo "❌ Basic cluster validation failed"
                fi
            else
                echo "❌ Node readiness validation failed"
            fi
        else
            echo "❌ Cluster creation failed on attempt $attempt"
        fi
        
        if [[ $attempt -lt $MAX_RETRIES ]]; then
            echo "⏳ Waiting ${RETRY_DELAY}s before retry..."
            sleep $RETRY_DELAY
        fi
        
        ((attempt++))
    done
    
    echo "❌ Failed to provision cluster after $MAX_RETRIES attempts"
    return 1
}

# Function to display cluster summary
display_cluster_summary() {
    local cluster_name=$1
    local context="kind-${cluster_name}"
    
    echo ""
    echo "📊 Cluster Summary:"
    echo "==================="
    
    echo ""
    echo "🔗 Cluster Information:"
    kubectl cluster-info --context "$context"
    
    echo ""
    echo "🖥️ Node Status:"
    kubectl get nodes --context "$context" -o wide
    
    echo ""
    echo "🎯 Cluster ready for ingress deployment!"
}

# Main execution
main() {
    echo "📋 Cluster provisioning configuration:"
    echo "  - Cluster name: $CLUSTER_NAME"
    echo "  - Config file: $CONFIG_FILE"
    echo "  - Node ready timeout: ${NODE_READY_TIMEOUT}s"
    echo "  - Max retries: $MAX_RETRIES"
    
    # Verify prerequisites
    echo "🔍 Verifying prerequisites..."
    
    if ! command -v kind &> /dev/null; then
        echo "❌ kind not found. Please install kind first."
        exit 1
    fi
    echo "✅ kind found: $(kind version)"
    
    if ! command -v kubectl &> /dev/null; then
        echo "❌ kubectl not found. Please install kubectl first."
        exit 1
    fi
    echo "✅ kubectl found"
    
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo "❌ Config file not found: $CONFIG_FILE"
        exit 1
    fi
    echo "✅ Config file found: $CONFIG_FILE"
    
    # Provision cluster
    if provision_cluster "$CLUSTER_NAME" "$CONFIG_FILE"; then
        display_cluster_summary "$CLUSTER_NAME"
        echo "🎯 Next step: Run ./deploy-ingress.sh to deploy HTTP services"
        exit 0
    else
        echo "💥 Cluster provisioning failed after all attempts"
        exit 1
    fi
}

# Execute main function
main "$@"

