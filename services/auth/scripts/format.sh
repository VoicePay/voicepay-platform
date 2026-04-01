#!/usr/bin/env bash
# Run repository formatting with Black (and isort via pre-commit hooks if configured)
set -euo pipefail

echo "Running black across repo..."
python -m black .

echo "Formatting complete."
