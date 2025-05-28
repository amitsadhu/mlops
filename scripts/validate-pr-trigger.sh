#!/bin/bash
set -euo pipefail

# Validation script for PR trigger functionality
# This ensures our CI workflow is properly configured

echo "🔍 Validating PR trigger configuration..."

# Check if workflow file exists and is valid
WORKFLOW_FILE=".github/workflows/mlops-pipeline.yml"

if [[ ! -f "$WORKFLOW_FILE" ]]; then
    echo "❌ Workflow file not found: $WORKFLOW_FILE"
    exit 1
fi

# Validate YAML syntax (requires yq or python)
if command -v python3 &> /dev/null; then
    python3 -c "
import yaml
import sys

try:
    with open('$WORKFLOW_FILE', 'r') as f:
        yaml.safe_load(f)
    print('✅ YAML syntax is valid')
except yaml.YAMLError as e:
    print(f'❌ YAML syntax error: {e}')
    sys.exit(1)
"
else
    echo "⚠️  Python not available for YAML validation"
fi

# Check for required trigger configuration
if grep -q "pull_request:" "$WORKFLOW_FILE"; then
    echo "✅ Pull request trigger configured"
else
    echo "❌ Pull request trigger not found"
    exit 1
fi

# Validate branch configuration
if grep -q "branches.*main\|master" "$WORKFLOW_FILE"; then
    echo "✅ Default branch trigger configured"
else
    echo "❌ Default branch trigger not properly configured"
    exit 1
fi

echo "🎉 PR trigger validation completed successfully!"

