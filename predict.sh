#python2
python -c 'import base64, sys, json; img = base64.b64encode(open(sys.argv[1], "rb").read()); print json.dumps({"key":"0", "image_bytes": {"b64": img}})' $2 &> request.json
#python3
#python -c "import base64; import sys; import json; img = base64.b64encode(open(sys.argv[1], \"rb\").read()); print(json.dumps({\"key\":\"0\", \"image_bytes\": {\"b64\": img.decode()}}))" %2 &> request.json
gcloud ai-platform predict --model $1 --json-instances request.json > result.txt
rm request.json
cat result.txt