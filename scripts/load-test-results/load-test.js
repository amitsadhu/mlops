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
