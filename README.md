# MLOps CI/CD Pipeline with Kubernetes

A complete MLOps pipeline implementation featuring automated Kubernetes cluster provisioning, ingress management, service deployment, health validation, and load testing with GitHub Actions CI/CD integration.

## 🎯 Project Overview

This project implements a comprehensive MLOps pipeline that automatically:
- Provisions multi-node Kubernetes clusters using KinD
- Deploys NGINX ingress controller for HTTP traffic management
- Creates and manages HTTP echo services (foo/bar)
- Validates service health and connectivity
- Performs automated load testing with k6
- Reports results via GitHub PR comments

## 🏗️ Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   GitHub PR     │───▶│  GitHub Actions  │───▶│  KinD Cluster   │
│   Trigger       │    │     Workflow     │    │   (3 nodes)     │
└─────────────────┘    └──────────────────┘    └─────────────────┘
         ▲                        │                        │
         │                        │                        ▼
         │                        │               ┌─────────────────┐
         │                        │               │ Ingress + Apps  │
         │                        │               │ foo/bar services│
         │                        │               └─────────────────┘
         │                        │                        │
         │                        ▼                        ▼
         │               ┌──────────────────┐    ┌─────────────────┐
         │               │  Load Testing    │───▶│    Results      │
         │               │     (k6)         │    │   Collection    │
         │               └──────────────────┘    └─────────────────┘
         │                                                │
         │                                                ▼
         │                                       ┌─────────────────┐
         │                                       │   Performance   │
         │                                       │    Metrics      │
         │                                       └─────────────────┘
         │                                                │
         └────────────────────────────────────────────────┘
                              PR Comments

```

## 📋 Requirements Implemented

✅ **Task 1:** GitHub Actions CI workflow triggered on PR  
✅ **Task 2:** Multi-node Kubernetes cluster provisioning (3 nodes)  
✅ **Task 3:** NGINX Ingress controller deployment  
✅ **Task 4:** HTTP-echo deployments (foo/bar services)  
✅ **Task 5:** Ingress routing configuration (foo.localhost/bar.localhost)  
✅ **Task 6:** Health validation and connectivity testing  
✅ **Task 7:** Automated load testing with k6  
✅ **Task 8:** PR comment automation with results reporting  

## 🚀 Quick Start

### Prerequisites
- Docker
- kubectl
- KinD (Kubernetes in Docker)
- GitHub repository with Actions enabled

### Local Testing
Clone the repository
git clone  cd 
Make scripts executable
chmod +x scripts/*.sh
Run the complete pipeline locally
bash /scripts/provision-cluster.sh 
bash /scripts/deploy-ingress.sh 
bash /scripts/test-ingress.sh 
bash /scripts/load-test.sh


### CI/CD Testing
1. Create a pull request to `main` branch
2. GitHub Actions will automatically trigger the MLOps pipeline
3. Monitor progress in the Actions tab
4. View automated results in PR comments

## 📁 Project Structure

```
├── .github/workflows/ 
│   └── mlops-pipeline.yml          # Main CI/CD workflow 
├── config/ 
│       └── kind-cluster.yaml           # Kubernetes cluster configuration 
├── scripts/ 
│   ├── provision-cluster.sh        # Cluster provisioning automation 
    │   
    ├── deploy-ingress.sh           # Ingress and services deployment 
    │   
    ├── test-ingress.sh             # Health validation testing 
    │   
    └── load-test.sh                # k6 load testing execution
    |
    ├── load-test-results/              # Generated test artifacts 
|
└── README.md                       # This documentation
```

## 🔧 Configuration

### Cluster Configuration (`config/kind-cluster.yaml`)
- **Nodes:** 1 control-plane + 2 workers
- **Port Mappings:** 80, 443, 30080, 30081
- **Network:** Pod subnet 10.244.0.0/16, Service subnet 10.96.0.0/12

### Environment Variables
CLUSTER_NAME=mlops-test-cluster     # Kubernetes cluster name 
NODE_READY_TIMEOUT=300              # Node readiness timeout (seconds) 
VUS=10                              # Virtual users for load testing 
DURATION=30s                        # Load test duration


## 🧪 Testing Strategy

### 1. Cluster Provisioning (`provision-cluster.sh`)
- Creates 3-node KinD cluster with proper networking
- Validates node readiness and system pod health
- Performs DNS functionality testing
- Implements retry logic with exponential backoff

### 2. Ingress Deployment (`deploy-ingress.sh`)
- Deploys NGINX ingress controller
- Creates foo/bar HTTP echo services
- Configures ingress routing rules
- Waits for deployment readiness

### 3. Health Validation (`test-ingress.sh`)
- Tests ingress controller health
- Validates service endpoints
- Performs HTTP connectivity testing
- Comprehensive error reporting

### 4. Load Testing (`load-test.sh`)
- Deploys k6 load testing job in Kubernetes
- Generates randomized traffic to foo/bar services
- Collects performance metrics (response time, error rate, throughput)
- Creates detailed test reports

## 📊 Performance Metrics

The load testing captures:
- **Response Time:** Average, 95th percentile
- **Throughput:** Requests per second
- **Error Rate:** Percentage of failed requests
- **Success Rate:** Percentage of successful requests

### Quality Gates
- Response time (95th percentile) < 500ms
- Error rate < 10%
- All services must be healthy before testing

## 🔄 CI/CD Pipeline

### Workflow Triggers
- Pull request opened/updated to `main` branch
- Manual workflow dispatch

### Pipeline Stages
1. **Setup:** Checkout code, install dependencies
2. **Provision:** Create and validate Kubernetes cluster
3. **Deploy:** Install ingress controller and services
4. **Test:** Validate health and connectivity
5. **Load Test:** Execute performance testing
6. **Report:** Post results to PR comments
7. **Cleanup:** Upload artifacts and logs

### Artifacts
- Load test results and metrics
- Cluster debug logs (on failure)
- Performance reports in HTML/JSON format

## 📈 Monitoring and Observability

### Automated Reporting
- Real-time pipeline status in PR comments
- Detailed performance metrics
- Infrastructure configuration summary
- Service endpoint validation results

### Debug Information
- Comprehensive logging at each stage
- Artifact collection for post-mortem analysis
- Cluster state snapshots on failure

## 🛠️ Development

### Adding New Tests
1. Create test script in `scripts/` directory
2. Add execution step to `.github/workflows/mlops-pipeline.yml`
3. Update documentation

### Customizing Load Tests
- Modify `load-test-results/load-test.js` for different scenarios
- Adjust VUS and DURATION environment variables
- Add custom metrics and thresholds

### Extending Services
- Add new deployments in `deploy-ingress.sh`
- Configure additional ingress routes
- Update health validation in `test-ingress.sh`

## 🔍 Troubleshooting

### Common Issues
1. **Cluster provisioning timeout:** Increase `NODE_READY_TIMEOUT`
2. **Ingress not responding:** Check port mappings in kind-cluster.yaml
3. **Load test failures:** Verify service endpoints are accessible
4. **Script permissions:** Ensure scripts are executable (`chmod +x`)

### Debug Commands
Check cluster status
kubectl get nodes -o wide kubectl get pods –all-namespaces
Verify ingress
kubectl get ingress kubectl describe ingress echo-ingress
Test connectivity
curl -H “Host: foo.localhost” http://localhost/ curl -H “Host: bar.localhost” http://localhost/


## 📝 Best Practices Implemented

### DevOps Excellence
- **Infrastructure as Code:** Declarative YAML configurations
- **Immutable Infrastructure:** Container-based deployments
- **Progressive Validation:** Step-by-step health checks
- **Fail-Fast Approach:** Early error detection and reporting

### MLOps Principles
- **Automated Testing:** Comprehensive validation pipeline
- **Continuous Integration:** PR-triggered workflows
- **Observability:** Detailed metrics and logging
- **Reproducibility:** Consistent environment provisioning

### Code Quality
- **Error Handling:** Graceful failure management
- **Documentation:** Comprehensive inline comments
- **Modularity:** Separate scripts for distinct functions
- **Maintainability:** Clear separation of concerns

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- **KinD:** Kubernetes in Docker for local cluster provisioning
- **NGINX Ingress:** Production-grade ingress controller
- **k6:** Modern load testing framework
- **GitHub Actions:** CI/CD automation platform

---

**Project Status:** ✅ Production Ready  
**Last Updated:** May 28, 2025  
**Pipeline Version:** v1.0.0

Time taken : Around 5 hours
