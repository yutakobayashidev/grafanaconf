#!/bin/bash

# Default parameters
METHOD="GET"
KEY=$(cat "${0%/*}/apikey")
API="https://api.ouraring.com/v2/usercollection/daily_readiness"
INCLUDE_DATA=("temperature_deviation" "temperature_trend_deviation")
LOKI_URL="http://localhost:3100/loki/api/v1/push"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -Method)
            METHOD="$2"
            shift 2
            ;;
        -Key)
            KEY="$2"
            shift 2
            ;;
        -Api)
            # Remove any accidental escapes from the URL
            API=$(echo "$2" | sed 's/\\&/\&/g')
            shift 2
            ;;
        -IncludeData)
            # Convert comma-separated string to array
            IFS=',' read -ra INCLUDE_DATA <<< "$2"
            shift 2
            ;;
        -LokiUrl)
            LOKI_URL="$2"
            shift 2
            ;;
        *)
            echo "Unknown parameter: $1"
            exit 1
            ;;
    esac
done

# Fetch data from Oura API
response=$(curl -s -f -X "$METHOD" -H "Authorization: Bearer $KEY" "$API" 2>&1)
curl_status=$?
if [ $curl_status -ne 0 ]; then
    echo "Error: Failed to fetch data from Oura API (status: $curl_status)"
    exit 1
fi

# Extract the API endpoint name for Loki stream
oura_endpoint=$(echo "$API" | sed -E 's/^.*\/([^?]*).*?$/\1/')

# Check if response contains data
if ! echo "$response" | jq -e '.data' > /dev/null; then
    echo "Error: No data found in API response"
    exit 1
fi

# Process the response and create Loki-compatible values array
values=()
while IFS= read -r timestamp; do
    if [ -z "$timestamp" ]; then
        continue
    fi
    unix_ts=$(date -d "$timestamp" +%s%N)
    for key in "${INCLUDE_DATA[@]}"; do
        value=$(echo "$response" | jq -r --arg ts "$timestamp" --arg key "$key" '
            .data[] | 
            select(.timestamp == $ts or .day == $ts) | 
            (.[$key] // .contributors[$key] // empty) | 
            select(. != null)
        ')
        if [ ! -z "$value" ]; then
            # Format for Loki: ["timestamp","key=value"]
            values+=("[\"$unix_ts\",\"$key=$value\"]")
        fi
    done
done < <(echo "$response" | jq -r '.data[].timestamp // .data[].day // empty')

# Create JSON payload for Loki
json_payload=$(cat <<EOF
{
    "streams": [
        {
            "stream": {
                "oura": "$oura_endpoint"
            },
            "values": [$(IFS=,; echo "${values[*]}")]
        }
    ]
}
EOF
)

# Send data to Loki
curl_response=$(curl -v -X POST \
    -H "Content-Type: application/json" \
    -d "$json_payload" \
    "$LOKI_URL" 2>&1)
curl_status=$?

if [ $curl_status -ne 0 ]; then
    echo "Error sending data to Loki (status: $curl_status)"
    exit 1
fi

# Check for HTTP 400 error in response
if echo "$curl_response" | grep -q "HTTP/1.1 400"; then
    echo "Error: Loki returned HTTP 400 Bad Request"
    echo "Please check the payload format"
    exit 1
fi

echo "Successfully sent data to Loki"
