# GitOps

## Recommendation

Use ArgoCD for this platform. It has strong enterprise RBAC, ApplicationSets, health checks, sync waves, progressive environment promotion patterns, and broad operator familiarity.

## Promotion Strategy

1. CI builds immutable images and signs them.
2. CI updates the dev Helm values digest.
3. ArgoCD syncs dev automatically.
4. QA, stage, and prod require pull-request promotion of values files.
5. Prod sync uses manual approval and sync windows.
