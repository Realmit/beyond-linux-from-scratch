# Make executable
chmod +x validate_urls.py

# Validate sources.list file
python3 validate_urls.py packages/sources.list

# With more details
python3 validate_urls.py packages/sources.list --verbose

# With longer timeout for large files
python3 validate_urls.py packages/sources.list --timeout 30

# With more workers
python3 validate_urls.py packages/sources.list --workers 20

# Save report elsewhere
python3 validate_urls.py packages/sources.list --output validation_report.txt

# Quiet mode (no live output)
python3 validate_urls.py packages/sources.list --quiet

# Help
python3 validate_urls.py --help