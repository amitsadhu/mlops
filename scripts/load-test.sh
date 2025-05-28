#!/bin/bash
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-mlops-test-cluster}"
CONTEXT="kind-${CLUSTER_NAME}"
VUS="${VUS:-10}"
DURATION="${DURATION:-30s}"
OUTPUT_DIR="load-test-results"

echo "🚀 Starting k6 load testing for foo and bar services..."

# Create k6 test script
create_k6_test_script() {
    echo "📝 Creating k6 load test script..."
    
    mkdir -p "$OUTPUT_DIR"
    
    cat > "$OUTPUT_DIR/load-test.js" << 'EOF'
import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate } from 'k6/metrics';

// Custom metrics
export let errorRate = new Rate('errors');

export let options = {
  vus: __ENV.VUS || 10,
  duration: __ENV.DURATION || '30s',
  thresholds: {
    http_req_duration: ['p(95)<500'], // 95% of requests must complete below 500ms
    http_req_failed: ['rate<0.1'],    // Error rate must be below 10%
  },
};

export default function() {
  // Randomize between foo and bar hosts
  const hosts = ['foo.localhost', 'bar.localhost'];
  const host = hosts[Math.floor(Math.random() * hosts.length)];
  
  // Use the ingress controller service instead of localhost
  let response = http.get('http://ingress-nginx-controller.ingress-nginx.svc.cluster.local/', {
    headers: { 'Host': host },
  });
  
  let success = check(response, {
    'status is 200': (r) => r.status === 200,
    'response time < 500ms': (r) => r.timings.duration < 500,
    'correct response body': (r) => {
      // Add null check to prevent TypeError
      if (!r.body) {
        console.log(`No response body for ${host}`);
        return false;
      }
      
      if (host === 'foo.localhost') {
        return r.body.includes('foo');
      } else {
        return r.body.includes('bar');
      }
    },
  });
  
  // Log response details for debugging
  if (!success) {
    console.log(`Request to ${host} failed. Status: ${response.status}, Body: ${response.body}`);
  }
  
  errorRate.add(!success);
  
  sleep(Math.random() * 2); // Random sleep between 0-2 seconds
}

export function handleSummary(data) {
  return {
    '/data/artifacts/summary.json': JSON.stringify(data, null, 2),
    '/data/artifacts/summary.html': htmlReport(data),
  };
}

function htmlReport(data) {
  return `
<!DOCTYPE html>
<html>
<head>
    <title>Load Test Results</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .metric { margin: 10px 0; padding: 10px; border: 1px solid #ddd; }
        .pass { background-color: #d4edda; }
        .fail { background-color: #f8d7da; }
    </style>
</head>
<body>
    <h1>Load Test Results</h1>
    <h2>Summary</h2>
    <div class="metric">
        <strong>Total Requests:</strong> ${data.metrics.http_reqs.values.count}
    </div>
    <div class="metric">
        <strong>Request Rate:</strong> ${data.metrics.http_reqs.values.rate.toFixed(2)} req/s
    </div>
    <div class="metric">
        <strong>Average Response Time:</strong> ${data.metrics.http_req_duration.values.avg.toFixed(2)}ms
    </div>
    <div class="metric">
        <strong>95th Percentile:</strong> ${data.metrics.http_req_duration.values['p(95)'].toFixed(2)}ms
    </div>
    <div class="metric">
        <strong>Error Rate:</strong> ${(data.metrics.http_req_failed.values.rate * 100).toFixed(2)}%
    </div>
</body>
</html>`;
}
EOF
    
    echo "✅ k6 test script created"
}


# Deploy k6 test using Kubernetes
deploy_k6_test() {
    echo "📦 Deploying k6 load test in Kubernetes..."
    
    # Create configmap with test script
    kubectl create configmap k6-test-script \
        --from-file="$OUTPUT_DIR/load-test.js" \
        --context "$CONTEXT" \
        --dry-run=client -o yaml | kubectl apply --context "$CONTEXT" -f -
    
    # Create k6 test job
    cat <<EOF | kubectl apply --context "$CONTEXT" -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: k6-load-test
spec:
  template:
    spec:
      containers:
      - name: k6
        image: grafana/k6:latest
        command: ["k6", "run", "/scripts/load-test.js"]
        env:
        - name: VUS
          value: "$VUS"
        - name: DURATION
          value: "$DURATION"
        - name: K6_WEB_DASHBOARD
          value: "true"
        - name: K6_WEB_DASHBOARD_EXPORT
          value: "/data/artifacts/k6-report.html"
        volumeMounts:
        - name: test-script
          mountPath: /scripts
        - name: artifacts
          mountPath: /data/artifacts
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 512Mi
      volumes:
      - name: test-script
        configMap:
          name: k6-test-script
      - name: artifacts
        emptyDir: {}
      restartPolicy: Never
  backoffLimit: 3
EOF
    
    echo "✅ k6 test job deployed"
}

# Wait for test completion and collect results
collect_test_results() {
    echo "📊 Collecting test results..."
    
    # Get job status first
    local job_status=$(kubectl get job k6-load-test --context "$CONTEXT" -o jsonpath='{.status.conditions[0].type}' 2>/dev/null || echo "Unknown")
    echo "🔍 Job status: $job_status"
    
    # Get pod name for the job
    local pod_name=$(kubectl get pods --selector=job-name=k6-load-test --context "$CONTEXT" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    
    if [[ -n "$pod_name" ]]; then
        echo "📋 Getting logs from pod: $pod_name"
        
        # Get logs with better error handling
        if kubectl logs "$pod_name" --context "$CONTEXT" > "$OUTPUT_DIR/k6-output.log" 2>&1; then
            echo "✅ Logs collected successfully"
        else
            echo "❌ Failed to collect logs"
            kubectl describe pod "$pod_name" --context "$CONTEXT" > "$OUTPUT_DIR/pod-debug.log"
            return 1
        fi
    else
        echo "❌ No pod found for k6 job"
        kubectl get pods --context "$CONTEXT" > "$OUTPUT_DIR/all-pods.log"
        return 1
    fi
    
    # Parse metrics with improved extraction
    echo "📈 Extracting performance metrics..."
    
    if [[ -f "$OUTPUT_DIR/k6-output.log" ]]; then
        # Extract metrics from k6 summary output (look for the final summary)
        local avg_duration=$(grep -E "http_req_duration.*avg=" "$OUTPUT_DIR/k6-output.log" | tail -1 | sed -n 's/.*avg=\([0-9.]*\)ms.*/\1/p' || echo "N/A")
        local p95_duration=$(grep -E "http_req_duration.*p\(95\)=" "$OUTPUT_DIR/k6-output.log" | tail -1 | sed -n 's/.*p(95)=\([0-9.]*\)ms.*/\1/p' || echo "N/A")
        local req_rate=$(grep -E "http_reqs.*[0-9.]+/s" "$OUTPUT_DIR/k6-output.log" | tail -1 | sed -n 's/.*\([0-9.]*\)\/s.*/\1/p' || echo "N/A")
        local error_rate=$(grep -E "http_req_failed.*[0-9.]+%" "$OUTPUT_DIR/k6-output.log" | tail -1 | sed -n 's/.*\([0-9.]*\)%.*/\1/p' || echo "N/A")
        local total_requests=$(grep -E "http_reqs.*[0-9]+" "$OUTPUT_DIR/k6-output.log" | tail -1 | sed -n 's/.*http_reqs[^0-9]*\([0-9]*\).*/\1/p' || echo "N/A")
        
        # Alternative extraction method - look for check results
        local success_rate=$(grep -E "✓.*[0-9.]+%" "$OUTPUT_DIR/k6-output.log" | head -1 | sed -n 's/.*\([0-9.]*\)%.*/\1/p' || echo "N/A")
        
        # If standard parsing fails, try to extract from the summary section
        if [[ "$avg_duration" == "N/A" ]]; then
            echo "🔍 Trying alternative metric extraction..."
            
            # Look for the final summary block
            local summary_start=$(grep -n "✓\|✗" "$OUTPUT_DIR/k6-output.log" | tail -10)
            echo "📋 Summary section found: $summary_start"
            
            # Extract from checks section if available
            local checks_passed=$(grep -c "✓" "$OUTPUT_DIR/k6-output.log" || echo "0")
            local checks_failed=$(grep -c "✗" "$OUTPUT_DIR/k6-output.log" || echo "0")
            local total_checks=$((checks_passed + checks_failed))
            
            if [[ $total_checks -gt 0 ]]; then
                success_rate=$(echo "scale=2; $checks_passed * 100 / $total_checks" | bc -l 2>/dev/null || echo "N/A")
                error_rate=$(echo "scale=2; $checks_failed * 100 / $total_checks" | bc -l 2>/dev/null || echo "N/A")
            fi
        fi
        
        # Create summary report with available metrics
        cat > "$OUTPUT_DIR/test-summary.md" << EOF
# Load Test Results

## Test Configuration
- **Virtual Users (VUs):** $VUS
- **Duration:** $DURATION
- **Target Services:** foo.localhost, bar.localhost
- **Job Status:** $job_status

## Performance Metrics
- **Average Response Time:** ${avg_duration}ms
- **95th Percentile Response Time:** ${p95_duration}ms
- **Request Rate:** ${req_rate} req/s
- **Total Requests:** ${total_requests}
- **Success Rate:** ${success_rate}%
- **Error Rate:** ${error_rate}%

## Test Status
$(if [[ "$error_rate" != "N/A" && "$error_rate" != "" ]] && (( $(echo "$error_rate < 10" | bc -l 2>/dev/null || echo 0) )); then echo "✅ **PASSED** - Error rate below 10%"; elif [[ "$success_rate" != "N/A" && "$success_rate" != "" ]] && (( $(echo "$success_rate > 90" | bc -l 2>/dev/null || echo 0) )); then echo "✅ **PASSED** - Success rate above 90%"; else echo "❌ **FAILED** - Error rate above 10% or metrics unavailable"; fi)

## Detailed Metrics Extraction Debug
- Checks Passed: $checks_passed
- Checks Failed: $checks_failed
- Total Checks: $total_checks

## Raw Logs Sample
\`\`\`
$(head -30 "$OUTPUT_DIR/k6-output.log")
...
$(tail -20 "$OUTPUT_DIR/k6-output.log")
\`\`\`
EOF
        
        echo "✅ Test results processed"
        
        # Debug: Show what we extracted
        echo "🔍 Extracted metrics:"
        echo "  - Average Duration: $avg_duration"
        echo "  - P95 Duration: $p95_duration"
        echo "  - Request Rate: $req_rate"
        echo "  - Success Rate: $success_rate"
        echo "  - Error Rate: $error_rate"
        
    else
        echo "❌ No log file found to process"
        return 1
    fi
}


# Display test summary
display_test_summary() {
    echo ""
    echo "📊 Load Test Summary:"
    echo "===================="
    
    if [[ -f "$OUTPUT_DIR/test-summary.md" ]]; then
        cat "$OUTPUT_DIR/test-summary.md"
    else
        echo "❌ Test summary not found"
        return 1
    fi
    
    echo ""
    echo "📁 Results saved to: $OUTPUT_DIR/"
    echo "📋 Full logs: $OUTPUT_DIR/k6-output.log"
    echo "📈 Summary: $OUTPUT_DIR/test-summary.md"
}

# Cleanup test resources
cleanup_test_resources() {
    echo "🧹 Cleaning up test resources..."
    
    kubectl delete job k6-load-test --context "$CONTEXT" --ignore-not-found=true
    kubectl delete configmap k6-test-script --context "$CONTEXT" --ignore-not-found=true
    
    echo "✅ Test resources cleaned up"
}

wait_for_job_completion() {
    echo "⏳ Waiting for load test to complete..."

    local timeout=600
    local start_time=$(date +%s)

    while true; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))

        if [[ $elapsed -gt $timeout ]]; then
            echo "❌ Timeout waiting for job completion"
            kubectl describe job k6-load-test --context "$CONTEXT"
            return 1
        fi

        # Check job status
        local job_status=$(kubectl get job k6-load-test --context "$CONTEXT" -o jsonpath='{.status.conditions[0].type}' 2>/dev/null || echo "Unknown")
        local active_pods=$(kubectl get job k6-load-test --context "$CONTEXT" -o jsonpath='{.status.active}' 2>/dev/null || echo "0")
        local succeeded_pods=$(kubectl get job k6-load-test --context "$CONTEXT" -o jsonpath='{.status.succeeded}' 2>/dev/null || echo "0")
        local failed_pods=$(kubectl get job k6-load-test --context "$CONTEXT" -o jsonpath='{.status.failed}' 2>/dev/null || echo "0")

        echo "📊 Job status: $job_status | Active: $active_pods | Succeeded: $succeeded_pods | Failed: $failed_pods (${elapsed}s elapsed)"

        if [[ "$job_status" == "Complete" || "$succeeded_pods" -gt 0 ]]; then
            echo "✅ Job completed successfully"
            return 0
        elif [[ "$job_status" == "Failed" || "$failed_pods" -gt 0 ]]; then
            echo "❌ Job failed"
            kubectl describe job k6-load-test --context "$CONTEXT"
            kubectl logs -l job-name=k6-load-test --context "$CONTEXT"
            return 1
        fi

        sleep 10
    done
}

# Main execution
main() {
    echo "📋 Load test configuration:"
    echo "  - Virtual Users: $VUS"
    echo "  - Duration: $DURATION"
    echo "  - Output Directory: $OUTPUT_DIR"
    
    # Verify prerequisites
    if ! kubectl cluster-info --context "$CONTEXT" &>/dev/null; then
        echo "❌ Cluster $CLUSTER_NAME not found"
        exit 1
    fi
    
    if ! kubectl get ingress echo-ingress --context "$CONTEXT" &>/dev/null; then
        echo "❌ Ingress not found. Run ./deploy-ingress.sh first"
        exit 1
    fi
    
    # Run load test
    create_k6_test_script
    deploy_k6_test
    
    if ! wait_for_job_completion; then
        echo "❌ Load test job failed to complete"
        cleanup_test_resources
        exit 1
    fi

    if collect_test_results; then
        display_test_summary
        cleanup_test_resources
        echo "🎉 Load testing completed successfully!"
        exit 0
    else
        echo "❌ Load testing failed"
        cleanup_test_resources
        exit 1
    fi
}

main "$@"

