#!/bin/sh
# Builds King_Maker.zip: one folder per addon at the top level.
# Tests, screenshots and git metadata stay out of the zip players download.
set -e
cd "$(dirname "$0")/AddOns"
rm -f ../King_Maker.zip
zip -qr ../King_Maker.zip . -x '*.DS_Store' -x '*/tests/*' -x '*/__pycache__/*' -x '*/screenshots/*' -x '*/.gitattributes' -x '*/.gitignore'
echo "Built King_Maker.zip"
