#!/bin/bash
pytest tests/ --cov=builder --cov-report=term --cov-report=html --cov-report=annotate
open htmlcov/index.html 2>/dev/null || echo "📊 Coverage report in htmlcov/"