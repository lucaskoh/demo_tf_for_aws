# Layers and state

How the repository is organised, how the state is stored and how the layers hand values to each other.

The environment is split into four layers that are applied in this order: `network`, `compute`, then `workloads` and `edge`. Each layer reads what it needs from the layers before it (see [How layers share values](#how-layers-share-values)). `make apply LAYER=compute` applies that layer and then the ones after it; `ONLY=1` applies just the one (see [Operations](operations.md)). Because the Kubernetes resources live in their own layer (`workloads`), which is configured from the EKS cluster that `compute` creates, no `-target` workaround is needed on the first deployment.

## Repository Layout

```
demo_tf_for_aws/
├── README.md                 # what the project is, the architecture, quick start
├── docs/                     # the rest of the documentation (these pages)
├── LICENSE
├── .gitignore
├── Makefile                  # make help lists all targets
├── .github/
│   ├── workflows/
│   │   ├── terraform-plan.yml      # on PR: checks + plan comment
│   │   ├── terraform-apply.yml     # manual: apply all layers in order
│   │   └── terraform-destroy.yml   # manual: destroy all layers in reverse order
│   └── scripts/
│       ├── plan-layers.sh          # plans every layer of one environment, skips layers whose upstream is not deployed
│       ├── apply-layer.sh          # applies one layer of one environment
│       └── destroy-layer.sh        # destroys one layer, retrying a few times
├── assets/                   # images uploaded to S3 by Terraform
│   ├── eks-logo.png
│   └── ec2-logo.png
├── bootstrap/                # one-time: state bucket + GitHub OIDC roles
├── modules/                  # reusable building blocks
│   ├── vpc/
│   ├── vpc-peering/
│   ├── security-group/       # one generic security group + rules map (used 3 times)
│   ├── s3-assets/
│   ├── ec2-instance/         # one EC2 instance created from an image template
│   ├── eks/
│   ├── k8s-app/
│   ├── alb/
│   ├── nlb/
│   ├── dns/
│   ├── env-resolver/         # turns the app files into workloads, instances, backends + the rules (has tests)
│   ├── ssm-publisher/        # publishes values as SSM parameters (end of a layer)
│   └── ssm-reader/           # reads what a layer before it published (start of a layer)
├── layers/                   # Terraform code of the four layers, shared by every environment
│   ├── network/              # VPCs, peering, security groups
│   ├── compute/              # S3 assets, EC2, EKS
│   ├── workloads/            # Kubernetes Deployment + Service
│   └── edge/                 # ALB, NLB, Route 53
├── templates/
│   ├── demo-page.html.tftpl  # the demo page (EKS and EC2)
│   └── ec2/                  # EC2 image templates: templates.yaml + one user data file each
├── schemas/
│   ├── values.schema.json    # JSON Schema of envs/<environment>/values.yaml (platform settings)
│   ├── apps.schema.json      # JSON Schema of the files under envs/<environment>/apps/
│   ├── ec2-templates.schema.json
│   └── tests/                # valid and invalid examples of the schemas
├── scripts/
│   ├── tf.sh                 # runs terraform for one environment and layer (backend + environment)
│   ├── validate-values.py    # checks values.yaml and the EC2 templates against the schemas
│   ├── test-schemas.sh       # runs the schema fixtures
│   ├── requirements.txt      # Python packages of the two scripts above
│   └── check-docs.py         # checks the links of README.md and docs/*.md
└── envs/
    └── demo/                 # an environment is a folder with a values.yaml and its app files, no Terraform code
        ├── values.yaml       # platform settings: common, network, compute
        └── apps/             # what the teams declare: workloads, instances, backends (any number of files)
            └── demo.yaml
```

Each folder under `layers/` is a complete root module with its own `backend.tf`, `versions.tf`, `variables.tf`, `values.tf` (reads the platform file `envs/<environment>/values.yaml`; only the network layer also reads the app files) and `main.tf`. `network`, `compute` and `edge` also have `providers.tf`, `locals.tf` and `outputs.tf`; `workloads` is smaller (its `providers.tf` configures the Kubernetes provider, and it has no outputs). `compute` and `edge` also declare the values that come from GitHub variables and secrets, and ship a `terraform.tfvars.example`. The layers are shared by all environments: the environment is chosen with the `environment` variable, which `scripts/tf.sh` sets (see [Environments](configuration.md#environments)).

## Remote State

Terraform state is stored in an **S3 bucket** (created by `bootstrap/`), never in Git.

| Feature | Setting |
|---|---|
| Versioning | Enabled (old versions expire after 90 days) |
| Encryption | SSE-S3 (AES256) |
| Public access | Fully blocked; plain HTTP requests denied |
| Locking | S3 native locking (`use_lockfile = true`, Terraform >= 1.10), no DynamoDB needed |
| Access logs | S3 server access logs (who read or wrote what, and when) go to a second bucket, `<state bucket>-logs`, and are kept for 90 days. The log bucket is private, encrypted, versioned and TLS-only |

## State layout

The environment is split into four states, one per layer. The key is `aws-multi-vpc/<environment>/<layer>/terraform.tfstate`; the table shows it for `demo`. A layer reads **only its own state**; what it needs from the other layers it reads from SSM parameters (see below).

| Layer | State key | Reads (SSM) | Publishes (SSM) |
|---|---|---|---|
| `network` | `aws-multi-vpc/demo/network/terraform.tfstate` | nothing | VPC and subnet IDs, security group IDs, the resolved `workloads`, `instances` and `backends` |
| `compute` | `aws-multi-vpc/demo/compute/terraform.tfstate` | `network` | EC2 private IPs per instance, EKS cluster endpoint, CA, name and ASG name, S3 object URLs |
| `workloads` | `aws-multi-vpc/demo/workloads/terraform.tfstate` | `network`, `compute` | nothing |
| `edge` | `aws-multi-vpc/demo/edge/terraform.tfstate` | `network`, `compute` | nothing (the URLs are outputs) |

- **Apply order:** `network`, `compute`, then `workloads` and `edge` (independent of each other). **Destroy order:** the reverse. `workloads` must be destroyed before `compute`, because the Kubernetes provider needs the cluster.
- A layer can only be planned after the layers it reads have been applied, because it reads their real, applied values. On a fresh account only `network` can be planned.
- `workloads` is a separate layer so the Kubernetes provider is configured from the parameters of the `compute` layer instead of from a resource in the same state.

> State files can contain secrets in plain text and Git has no locking, so committing `terraform.tfstate` is unsafe.
> The provided `.gitignore` should exclude `*.tfstate*`, `.terraform/`, and `terraform.tfvars`.

## How layers share values

A layer publishes the few values that other layers need as **SSM parameters**, and a layer reads the parameters of the layers before it. No layer reads another layer's Terraform state.

- **Names:** `/tf-platform/<environment>/<layer>/<name>`, for example `/tf-platform/demo/network/vpc_a_id`. (SSM does not allow a name that starts with `aws` or `ssm`.)
- **Format:** each value is stored as JSON, so lists and objects come back with the shape they were published with. The type is `String`: the values are not secrets (IDs, endpoints, a public certificate), and the CI plan role can read them without access to a KMS key.
- **Publishing:** `layers/network/ssm.tf` and `layers/compute/ssm.tf` list exactly what is published (`modules/ssm-publisher`). When a layer needs another value from an earlier layer, add it there first. `outputs.tf` is only the list of outputs for people.
- **Reading:** `modules/ssm-reader` reads everything under a path. If there is nothing, `plan` fails with "apply the layer that publishes them first", and the CI plan reports such a layer as *skipped*.
- **Size and cost:** a standard parameter holds 4 KB. A value that is bigger is moved to the advanced tier automatically (8 KB, about US$0.05 per month for that parameter); above 8 KB the plan fails with a message. Everything else is free.
- The parameters belong to the layer that publishes them: destroying the layer deletes them.
