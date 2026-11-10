# Planned architecture changes

The goal is a small internal platform: the platform team owns the Terraform code, the modules and the guardrails, and other people deploy by editing one `values.yaml`.

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

**Planned, in this order**

1. **Split `values.yaml` by owner.** Today one file mixes what the platform decides (`common`, `network`, `compute`) with what users decide (`workloads`, `instances`, `backends`). The plan is to keep `envs/<environment>/values.yaml` for the platform part and to move the user part to `envs/<environment>/apps/*.yaml`: one file per team or application, any number of files. The files are merged as a union, and a name that is defined twice is an error that names both files (nothing is overridden). Only the network layer reads these sections, so the merge lives in one place.
2. **Separate who may change what.** `CODEOWNERS` works per file, which is why the split comes first: the platform owns `layers/`, `modules/`, `templates/`, `schemas/` and the `values.yaml` of each environment, and a team owns its own file under `apps/`. With a single maintainer, `CODEOWNERS` starts as automatic review requests only; "require review from code owners" can be turned on once a second account or team exists (nobody can approve their own pull request). An allowlist for container images and versioned platform code belong here too.

**Later**

- **Optional components.** Switches such as `eks.enabled` or `dns.enabled`, with checks for combinations that make no sense.
- **A least-privilege apply role**, as described in [From demo to production: the apply role](ci-cd.md#from-demo-to-production-the-apply-role).
- **A real deployment of the optional DNS record (Route 53) and of a second environment.** Both are only exercised by `plan` today.

**Deliberate shortcuts of the demo, and the production pattern**

These keep the demo in one repository with the fewest moving parts.

- **Kubernetes objects are applied by Terraform.** The `workloads` layer applies the Deployments and Services from the CI runner. The production pattern is a separate Kubernetes repository delivered by GitOps (Argo CD or Flux), while this repository keeps network, compute and edge. Terraform already publishes the cluster name, endpoint and CA as SSM parameters, which is what the other side would read. A GitOps controller pulls from Git from inside the cluster, so the CI runner would no longer need to reach the Kubernetes API, and the public EKS endpoint could be narrowed.
- **EKS backends are reached through the node group's Auto Scaling group and a NodePort.** The alternative that fits this architecture is the AWS Load Balancer Controller with `TargetGroupBinding`: Terraform keeps the ALB and creates `ip` target groups, and the controller registers the pods directly. That removes the limit of 10 backends per Auto Scaling group, the extra hop through the node, the node-level health checks and the NodePort rules, and it is also what lets the Kubernetes objects live in another repository without sharing NodePorts. It needs the controller, an IAM role for it and `ip` target groups, so it is not done in the demo.
- **The Kubernetes Gateway API** was considered and not chosen: the AWS Load Balancer Controller would create its own ALB, but here one ALB is owned by Terraform and shared by the EKS and EC2 backends and by the NLB in front of it.
