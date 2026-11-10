# Planned architecture changes

The goal is a small internal platform: the platform team owns the Terraform code, the modules and the guardrails, and other people deploy by editing a few YAML files.

**Done**

1. **Split state.** One state per layer (`network`, `compute`, `workloads`, `edge`), so a change in one area has a smaller blast radius and parts of the environment can be created or destroyed independently.
2. **Group by nature.** Each layer is its own root module. Layers share values through SSM parameters.
3. **Drive configuration with `yamldecode`.** Each layer reads `envs/<environment>/values.yaml`; only values that come from GitHub variables and secrets remain Terraform variables.
4. **Normalize the modules.** Modules do not know about this demo: one generic `security-group` module, and ports, paths, health checks, sizes and instance types are inputs with a `description`, a default and a `validation` where a wrong value would fail late.
5. **Add a `values.yaml`.** The environment-specific values live in `envs/<environment>/values.yaml`.
6. **Environments are values-only.** The layer code is shared; a new environment is a new folder under `envs/` (see [Environments](configuration.md#environments)).
7. **Declare what runs and how it is routed.** `workloads`, `instances` and `backends` in `values.yaml`; the platform creates the rest and rejects mistakes in `plan` (see [Workloads, instances and backends](configuration.md#workloads-instances-and-backends)).
8. **EC2 image templates.** Instances must use a template provided by the platform team (see [EC2 image templates](configuration.md#ec2-image-templates)).
9. **Validate `values.yaml` against a schema.** JSON Schema checks in CI (with annotations on the pull request), locally and in the editor (see [Configuration](configuration.md#configuration)).
10. **SSM parameters instead of `terraform_remote_state`.** Each layer publishes the few values that others read, and no layer reads another layer's state (see [How layers share values](layers-and-state.md#how-layers-share-values)).
11. **Split `values.yaml` by owner.** The platform file `envs/<environment>/values.yaml` (`common`, `network`, `compute`) and any number of app files under `envs/<environment>/apps/` (`workloads`, `instances`, `backends`). The files are merged as a union, a name that is defined twice is an error that names both files, and a backend may point to a workload of another file (see [App files](configuration.md#app-files)).
12. **Resolver as a tested module.** The code that merges the app files, derives the numbers and checks the rules is `modules/env-resolver`, covered by `terraform test` (see [Where the rules live](configuration.md#workloads-instances-and-backends)).
13. **Owners per file.** `.github/CODEOWNERS` requests a review from the platform owner for the platform paths and has a place for each team's app files. It only requests reviews for now: "require review from code owners" cannot be satisfied by a single maintainer (nobody approves their own pull request) and stays off until a second account or team exists.
14. **Container image allowlist.** `common.allowed_images` restricts where workload images may come from (see [Allowed images](configuration.md#allowed-images)); `common.image_proxies` pulls every image through your own proxy registry such as Harbor (see [Proxy registry](configuration.md#proxy-registry-harbor-and-similar)).
15. **Versioned platform code.** An environment can pin a released version of the code (`common.platform_version`, a git tag), so a change rolls out environment by environment (see [Platform versions](configuration.md#platform-versions) and [Releases](ci-cd.md#releases)).
16. **Platform as a remote.** An environment repository holds only `envs/` and runs a version of this platform from a git URL (`common.platform_source` + `platform_version`, `./platform <environment> <layer> ...`), see [Environment repository](configuration.md#environment-repository).

**Next**

- **CI for an environment repository.** Reusable `workflow_call` workflows in the platform repository, a second repository with its secrets and `production` environment, and AWS roles that trust it (a change in `bootstrap/`). Optionally a pinned commit SHA next to the tag and an allowlist of platform sources.
- **Optional components.** Switches such as `eks.enabled` or `dns.enabled`, with checks for combinations that make no sense.
- **A least-privilege apply role**, as described in [From demo to production: the apply role](ci-cd.md#from-demo-to-production-the-apply-role).
- **A real deployment of the optional DNS record (Route 53) and of a second environment.** Both are only exercised by `plan` today.

**Deliberate shortcuts of the demo, and the production pattern**

These keep the demo in one repository with the fewest moving parts.

- **Kubernetes objects are applied by Terraform.** The `workloads` layer applies the Deployments and Services from the CI runner. The production pattern is a separate Kubernetes repository delivered by GitOps (Argo CD or Flux), while this repository keeps network, compute and edge. Terraform already publishes the cluster name, endpoint and CA as SSM parameters, which is what the other side would read. A GitOps controller pulls from Git from inside the cluster, so the CI runner would no longer need to reach the Kubernetes API, and the public EKS endpoint could be narrowed.
- **EKS backends are reached through the node group's Auto Scaling group and a NodePort.** The alternative that fits this architecture is the AWS Load Balancer Controller with `TargetGroupBinding`: Terraform keeps the ALB and creates `ip` target groups, and the controller registers the pods directly. That removes the limit of 10 backends per Auto Scaling group, the extra hop through the node, the node-level health checks and the NodePort rules, and it is also what lets the Kubernetes objects live in another repository without sharing NodePorts. It needs the controller, an IAM role for it and `ip` target groups, so it is not done in the demo.
- **The Kubernetes Gateway API** was considered and not chosen: the AWS Load Balancer Controller would create its own ALB, but here one ALB is owned by Terraform and shared by the EKS and EC2 backends and by the NLB in front of it.
