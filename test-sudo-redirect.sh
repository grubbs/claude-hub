#!/bin/bash
# Test how sudo behaves with redirects

echo "Test 1: Redirect outside sudo (current approach)"
sudo -u $USER echo "Hello from sudo" > /tmp/test1.txt 2>&1
echo "Exit code: $?"
echo "Output file contents:"
cat /tmp/test1.txt
echo "---"

echo "Test 2: Redirect inside sudo with sh -c"
sudo -u $USER sh -c 'echo "Hello from sudo" > /tmp/test2.txt 2>&1'
echo "Exit code: $?"
echo "Output file contents:"
cat /tmp/test2.txt
echo "---"

echo "Test 3: Using tee to capture output"
sudo -u $USER echo "Hello from sudo" | tee /tmp/test3.txt > /dev/null
echo "Exit code: $?"
echo "Output file contents:"
cat /tmp/test3.txt
echo "---"

# Clean up
rm -f /tmp/test*.txt