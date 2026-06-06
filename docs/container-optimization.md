# Container Optimization

## Baseline Findings

| Service | Existing concern | Optimization |
|---|---|---|
| Go services | Larger builder/runtime images possible | Multi-stage build to distroless static nonroot |
| Python services | Dependency and OS package bloat | Use slim builder and distroless Python runtime where compatible |
| Node.js services | Dev dependencies in runtime image | `npm ci --omit=dev`, non-root runtime |
| Java adservice | Large JRE image | Build layered jar, run on distroless Java |
| cartservice | Runtime image may include unnecessary SDK bits | Publish self-contained or ASP.NET runtime-only image |

## Standard Controls

- Run as non-root.
- Drop Linux capabilities.
- Use read-only root filesystem where compatible.
- Set explicit UID/GID.
- Generate SBOM with Syft.
- Sign images with Cosign keyless signing.
- Enforce signatures in CI.

## Example Go Dockerfile

```dockerfile
FROM golang:1.22-bookworm AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /app/service .

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /app/service /service
USER nonroot:nonroot
ENTRYPOINT ["/service"]
```

## CI Security Gates

Cosign signs pushed ECR images using GitHub OIDC. Dev deployments use immutable
commit-SHA tags. Container vulnerability scanning is currently disabled and can
be added back later.
