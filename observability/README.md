# Observability

Installs Prometheus, Alertmanager, Grafana, Fluent Bit, OpenSearch forwarding, OpenTelemetry Collector, Jaeger, CloudWatch, and X-Ray integrations.

Recommended deployment order:

1. `kube-prometheus-stack`
2. OpenTelemetry Collector
3. Fluent Bit
4. Jaeger
5. Dashboards and alert rules
