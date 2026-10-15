#!/bin/sh
# Builds King_Maker.zip: one folder per addon at the top level.
set -e
cd "$(dirname "$0")/AddOns"
rm -f ../King_Maker.zip
zip -qr ../King_Maker.zip . -x '*.DS_Store'
echo "Built King_Maker.zip"
