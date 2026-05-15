#!/bin/bash
# Run test suite with coverage

set -e

echo "=========================================="
echo "LFS Builder Test Suite"
echo "=========================================="

# Install test dependencies if needed
pip install -r requirements-test.txt 2>/dev/null || true

# Run tests with coverage
python -m pytest tests/ \
    -v \
    --cov=builder \
    --cov-report=html \
    --cov-report=term \
    --cov-report=xml \
    --tb=short \
    -n auto \
    "$@"

# Display coverage summary
echo ""
echo "=========================================="
echo "Coverage Report Summary"
echo "=========================================="
python -c "
import coverage
cov = coverage.Coverage()
cov.load()
total = cov.report()
if total < 80:
    print(f'⚠️ Coverage: {total:.1f}% (below 80%)')
else:
    print(f'✅ Coverage: {total:.1f}%')
"

echo ""
echo "HTML coverage report: ./htmlcov/index.html"