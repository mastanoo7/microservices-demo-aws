# Optional GitOps

The default deployment path is `.github/workflows/deploy.yml`, which applies the
Kustomize overlay directly through an SSM tunnel.

Do not enable these Argo CD examples for a cluster that is managed by the direct
GitHub Actions deployment workflow; two reconcilers would compete for ownership.
The manifests remain templates for teams that intentionally replace direct
deployment with Argo CD. Update `repoURL` before use.

## Promotion Strategy

1. CI builds immutable images and signs them.
2. A reviewed change updates the dev image reference.
3. Argo CD syncs dev automatically.
