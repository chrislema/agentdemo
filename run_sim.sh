#!/bin/bash
echo "Paste your API key (invisible), then press Enter:"
read -s ANTHROPIC_API_KEY
export ANTHROPIC_API_KEY
mix simulate --iterations 10 --verbose --save
