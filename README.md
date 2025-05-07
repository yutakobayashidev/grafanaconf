# grafanaconf

wip

```bash
docker run --name loki -d \
  -v $(pwd)/loki:/mnt/config \
  -p 3100:3100 \
  --user root \
  --entrypoint /bin/sh \
  --network loki-network \
  grafana/loki:3.4.1 \
  -c "mkdir -p /var/lib/loki && chown -R 10001:10001 /var/lib/loki && /usr/bin/loki -config.file=/mnt/config/config.yaml"

docker run --name promtail -d \
  -v $(pwd)/promtail:/mnt/config \
  -v /var/log:/var/log \
  --network loki-network \
  grafana/promtail:3.4.1 \
  -config.file=/mnt/config/config.yaml

docker run -d -p 3000:3000 --name=grafana \
  --volume grafana-storage:/var/lib/grafana \
  --network loki-network \
  grafana/grafana-enterprise
```