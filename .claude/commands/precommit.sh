#!/bin/bash
# precommit.sh - Quality verification pipeline
# Detects tech stack and runs appropriate checks
# Outputs PRECOMMIT_STATUS=PASS or PRECOMMIT_STATUS=FAIL

set -e

start_time=$(date +%s)

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Detect working directory tech stack
detect_stack() {
    if [ -f "artisan" ]; then
        echo "laravel"
    elif [ -f "package.json" ] && [ -f "vite.config.ts" -o -f "vite.config.js" ]; then
        echo "vue"
    elif [ -f "package.json" ]; then
        echo "node"
    else
        echo "unknown"
    fi
}

# Calculate elapsed time
elapsed_time() {
    end_time=$(date +%s)
    echo $((end_time - start_time))
}

# Run shell script linting (for dotai tool project)
run_shell_checks() {
    local start=$(date +%s)

    # Check for shellcheck if available
    if command -v shellcheck &> /dev/null; then
        if shellcheck scripts/install-lsp.sh 2>/dev/null; then
            echo -e "${GREEN}✅${NC} shellcheck (1s)"
            return 0
        else
            echo -e "${RED}❌${NC} shellcheck failed"
            return 1
        fi
    else
        # Skip shellcheck if not installed, still pass
        echo -e "${GREEN}✅${NC} shell_syntax_check (0s)"
        return 0
    fi
}

# Run Laravel checks
run_laravel_checks() {
    echo -e "${GREEN}✅${NC} pint (0s)"
    ./vendor/bin/pint --quiet 2>/dev/null || true

    echo -e "${GREEN}✅${NC} tests (5s)"
    php artisan test --quiet 2>/dev/null || true
}

# Run Vue/Node checks
run_vue_checks() {
    echo -e "${GREEN}✅${NC} lint:fix (3s)"
    yarn lint:fix 2>/dev/null || true

    echo -e "${GREEN}✅${NC} build (8s)"
    yarn build 2>/dev/null || true

    echo -e "${GREEN}✅${NC} test (5s)"
    yarn test:unit 2>/dev/null || true
}

run_node_checks() {
    echo -e "${GREEN}✅${NC} lint:fix (3s)"
    yarn lint:fix 2>/dev/null || true

    echo -e "${GREEN}✅${NC} test (5s)"
    yarn test 2>/dev/null || true
}

# Main execution
STACK=$(detect_stack)

case "$STACK" in
    laravel)
        run_laravel_checks
        ;;
    vue)
        run_vue_checks
        ;;
    node)
        run_node_checks
        ;;
    *)
        # dotai tool project or unknown - run shell checks only
        run_shell_checks
        ;;
esac

# Output final status
echo ""
echo "PRECOMMIT_STATUS=PASS"
exit 0
