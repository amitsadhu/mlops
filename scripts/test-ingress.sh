#!/bin/bash
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-mlops-test-cluster}"
CONTEXT="kind-${CLUSTER_NAME}"

echo "🧪 Testing ingress HTTP connectivity..."

# Test HTTP connectivity
test_http_connectivity() {
    echo "🔍 Testing HTTP services connectivity..."
    
    local test_passed=true
    
    # Test foo service
    echo "Testing foo.localhost..."
    if curl -s -H "Host: foo.localhost" http://localhost/ | grep -q "foo"; then
        echo "✅ foo.localhost: SUCCESS (returns 'foo')"
    else
        echo "❌ foo.localhost: FAILED"
        test_passed=false
    fi
    
    # Test bar service
    echo "Testing bar.localhost..."
    if curl -s -H "Host: bar.localhost" http://localhost/ | grep -q "bar"; then
        echo "✅ bar.localhost: SUCCESS (returns 'bar')"
    else
        echo "❌ bar.localhost: FAILED"
        test_passed=false
    fi
    
    if [[ "$test_passed" == true ]]; then
        echo "🎉 All HTTP connectivity tests passed!"
        return 0
    else
        echo "❌ Some HTTP connectivity tests failed"
        return 1
    fi
}

# Test ingress health
test_ingress_health() {
    echo "🔍 Testing ingress controller health..."
    
    # Check ingress controller pods
    local ingress_pods_ready
    ingress_pods_ready=$(kubectl get pods -n ingress-nginx --context "$CONTEXT" --no-headers | grep -c " Running " || echo "0")
    
    if [[ "$ingress_pods_ready" -gt 0 ]]; then
        echo "✅ Ingress controller pods: $ingress_pods_ready running"
    else
        echo "❌ No ingress controller pods running"
        return 1
    fi
    
    # Check ingress resource
    local ingress_count
    ingress_count=$(kubectl get ingress --context "$CONTEXT" --no-headers | wc -l || echo "0")
    
    if [[ "$ingress_count" -gt 0 ]]; then
        echo "✅ Ingress resources: $ingress_count configured"
    else
        echo "❌ No ingress resources found"
        return 1
    fi
    
    echo "✅ Ingress health check passed"
    return 0
}

# Test service endpoints
test_service_endpoints() {
    echo "🔍 Testing service endpoints..."
    
    # Check foo service endpoints
    local foo_endpoints
    foo_endpoints=$(kubectl get endpoints foo-service --context "$CONTEXT" -o jsonpath='{.subsets[0].addresses}' 2>/dev/null | jq length 2>/dev/null || echo "0")
    
    if [[ "$foo_endpoints" -gt 0 ]]; then
        echo "✅ foo-service endpoints: $foo_endpoints ready"
    else
        echo "❌ foo-service has no ready endpoints"
        return 1
    fi
    
    # Check bar service endpoints
    local bar_endpoints
    bar_endpoints=$(kubectl get endpoints bar-service --context "$CONTEXT" -o jsonpath='{.subsets[0].addresses}' 2>/dev/null | jq length 2>/dev/null || echo "0")
    
    if [[ "$bar_endpoints" -gt 0 ]]; then
        echo "✅ bar-service endpoints: $bar_endpoints ready"
    else
        echo "❌ bar-service has no ready endpoints"
        return 1
    fi
    
    echo "✅ Service endpoints check passed"
    return 0
}

# Comprehensive testing
run_comprehensive_tests() {
    echo "🧪 Running comprehensive ingress tests..."
    
    local all_tests_passed=true
    
    # Test 1: Ingress health
    if ! test_ingress_health; then
        all_tests_passed=false
    fi
    
    # Test 2: Service endpoints
    if ! test_service_endpoints; then
        all_tests_passed=false
    fi
    
    # Test 3: HTTP connectivity
    if ! test_http_connectivity; then
        all_tests_passed=false
    fi
    
    if [[ "$all_tests_passed" == true ]]; then
        echo "🎉 All ingress tests passed successfully!"
        echo "🎯 Next step: Run ./load-test.sh to perform load testing"
        return 0
    else
        echo "❌ Some ingress tests failed"
        return 1
    fi
}

# Debug information
show_debug_info() {
    echo ""
    echo "🔍 Debug Information:"
    echo "===================="
    
    echo ""
    echo "📊 Ingress Controller Status:"
    kubectl get pods -n ingress-nginx --context "$CONTEXT"
    
    echo ""
    echo "🔗 Services:"
    kubectl get services --context "$CONTEXT"
    
    echo ""
    echo "🌐 Ingress:"
    kubectl describe ingress echo-ingress --context "$CONTEXT"
    
    echo ""
    echo "📡 Endpoints:"
    kubectl get endpoints --context "$CONTEXT"
}

# Main execution
main() {
    # Verify cluster and ingress exist
    if ! kubectl cluster-info --context "$CONTEXT" &>/dev/null; then
        echo "❌ Cluster $CLUSTER_NAME not found"
        exit 1
    fi
    
    if ! kubectl get ingress echo-ingress --context "$CONTEXT" &>/dev/null; then
        echo "❌ Ingress not found. Run ./deploy-ingress.sh first"
        exit 1
    fi
    
    # Run tests
    if run_comprehensive_tests; then
        echo "✅ Ingress testing completed successfully!"
        exit 0
    else
        echo "❌ Ingress testing failed"
        show_debug_info
        exit 1
    fi
}

main "$@"

