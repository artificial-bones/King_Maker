#!/bin/sh
# Builds King_Maker.zip: the King_Maker folder (the whole addon) plus the 1.x stub folders that carry old
# saved data into it (docs/unified.md).
# Tests, screenshots and git metadata stay out of the zip players download.
set -e
cd "$(dirname "$0")/AddOns"
rm -f ../King_Maker.zip
zip -qr ../King_Maker.zip . -x '*.DS_Store' -x '*/tests/*' -x '*/__pycache__/*' -x '*/screenshots/*' -x '*/docs/*' -x '*.md' -x '*/.gitattributes' -x '*/.gitignore'
echo "Built King_Maker.zip"
