#!/bin/sh
# Builds King_Addons.zip: one folder per addon at the top level.
set -e
cd "$(dirname "$0")/AddOns"
rm -f ../King_Addons.zip
zip -qr ../King_Addons.zip . -x '*.DS_Store'
echo "Built King_Addons.zip"
