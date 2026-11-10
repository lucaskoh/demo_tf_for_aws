# Configuration

Configuration comes from two places:

1. **`envs/demo/values.yaml`** holds the environment values and is shared by all layers. Each layer reads it with `yamldecode(file(...))` in its `values.tf`, and checks it with preconditions (for example the name format, valid and non-overlapping CIDRs, and the workloads, instances and backends: targets, paths, ports and IPs). A new environment is a new values file.
2. **Variables** hold the values that come from outside the repository: set them in `terraform.tfvars` inside the layer folder (see the `terraform.tfvars.example` files); in CI they come from GitHub repository variables and secrets.

**`values.yaml` is checked against a schema** (`schemas/values.schema.json`) before anything is planned: unknown or misspelled keys (for example `replica` instead of `replicas`), wrong types, values out of range, missing required fields, and a backend without exactly one target are reported with the file and line, for example `envs/demo/values.yaml:24: workloads.web: unknown key 'replica' - did you mean 'replicas'?`. This runs

- locally: `make validate-values` (needs `python3 -m pip install -r scripts/requirements.txt`),
- in CI, where each error shows up as an annotation on the pull request, and
- in the editor: both YAML files start with a `# yaml-language-server: $schema=...` line, so the [YAML extension for VS Code](https://marketplace.visualstudio.com/items?itemName=redhat.vscode-yaml) offers completion, shows the description of each field and underlines mistakes while you type. Keep that line when you copy an environment.

The schema only checks the shape. What needs other data (a backend points to an existing workload or instance, paths, NodePorts, IPs and priorities are unique, the EC2 template exists) is checked by Terraform when the network layer is planned. When a field is added to the platform, the schema changes in the same pull request.

The layers use a partial S3 backend. `scripts/tf.sh` passes the bucket, region and state key to `terraform init` with `-backend-config`, taking the bucket and region from `common.state_bucket` and `common.region`, so `values.yaml` is the only place that has them. These two keys must be written as `key: value` on one line directly under `common:`, because `scripts/common-value.sh` reads them with `awk` instead of a YAML parser (so no extra tool is needed). `make validate-values` compares that reader with a real YAML parser and fails if they disagree.

**`values.yaml`**

| Key | Default | Description |
|---|---|---|
| `common.name` | `demo` | Name prefix for resources (1-20 chars: lowercase letters, digits, hyphens) |
| `common.region` | `ap-northeast-1` | AWS region |
| `common.state_bucket` | *(bucket name)* | State bucket (the Terraform backend of every layer) |
| `common.tags` | Project, Environment, ManagedBy | Default tags on every resource; each layer adds a `Layer` tag |
| `network.vpc_a_cidr` | `10.0.0.0/16` | CIDR of VPC-A |
| `network.vpc_b_cidr` | `10.1.0.0/16` | CIDR of VPC-B (must not overlap VPC-A) |
| `common.http_port` | `80` | Port of the NLB and ALB listeners, and of Nginx on the EC2 instances |
| `compute.ec2_instance_type` | `t3.micro` | Default instance type of the instances (an instance can override it) |
| `compute.eks` | Spot `t3.small`/`t3a.small`, 1 node (max 2) | Node group: `instance_types`, `capacity_type`, `desired_size`, `min_size`, `max_size`; optional `public_access_cidrs` (who may reach the Kubernetes API endpoint, default `0.0.0.0/0`, see [Limitations](architecture.md#limitations)) |
| `compute.kubernetes_version` | `null` | EKS version. `null` = the EKS default for new clusters |

## Workloads, instances and backends

`values.yaml` separates *what runs* from *how traffic reaches it*:

- `workloads:` are Deployments on the EKS cluster (image, replicas, ports).
- `instances:` are Nginx instances in VPC-B (instance type, IP).
- `backends:` are pure routes: a path on the ALB that leads to one workload or one instance. Nothing else.

The platform creates the pods or instances, the target groups, the routes and the security group rules. Nobody writes a security group rule or picks a NodePort.

```yaml
workloads:
  web:                      # no image: the built-in Nginx demo page is served
    replicas: 2
  api:
    image: hashicorp/http-echo:1.0
    container_port: 5678
    health_check_path: /api
  worker:                   # no backend routes to it: a ClusterIP Service, no NodePort, no rules
    image: busybox:1.36

instances:
  legacy:
    template: nginx-demo    # required: an EC2 image template
  reports:
    template: nginx-demo
    instance_type: t3.small

backends:
  home:    { path: home,    workload: web }
  landing: { path: landing, workload: web }       # a second path to the same workload
  api:     { path: api,     workload: api }
  legacy:  { path: legacy,  instance: legacy }
  reports: { path: reports, instance: reports }
```

Names are lowercase letters, digits and hyphens. `<common.name>-<backend name>-tg` must fit in 32 characters (target group name limit).

**Workload fields** (all optional)

| Field | Default | Description |
|---|---|---|
| `image` | none | Container image. Without it the built-in Nginx demo page is served at every path that routes to the workload |
| `container_port` | `80` | Port the container listens on (the demo page needs `80`) |
| `replicas` | `1` | Number of pods |
| `health_check_path` | `/` | Readiness probe. For a custom image it is also the default ALB health check |
| `node_port` | derived from the name | NodePort (30000-32767). Only workloads that a backend routes to get one |
| `page_title`, `page_heading` | from the name | Texts of the demo page (no `<`, `>`, `"` or line breaks) |

**Instance fields**: `template` (required, an [EC2 image template](#ec2-image-templates)); optional `instance_type` (default `compute.ec2_instance_type`), `private_ip` (default: AWS picks a free address of the VPC-B subnet; if you set one it must be inside the subnet and unique), `page_title`, `page_heading`.

**Backend fields**: `path` (required, one URL segment without slashes) and exactly one of `workload` or `instance` (required); optional `health_check_path` (ALB health check; default `/<path>/index.html` for the demo page) and `priority` (ALB rule priority 1-50000, derived from the name). The ALB forwards `/<path>` and `/<path>/*` without rewriting, so a custom image must serve under that prefix.

The NodePort and the priority are derived from the name with a hash, so adding or removing something never changes the numbers of the others. **Renaming is different:** a new name is a new hash, which is the same as removing the old entry and adding a new one. The NodePort or the priority change, the resources are replaced, and the traffic to them is interrupted while that happens. To keep a number, set `node_port` or `priority` explicitly (the resources are still replaced, because their names change).

If two entries get the same NodePort or priority (by chance, or because you set the same one twice), `plan` fails and tells you which entry to change and offers a free value, for example `workload 'beta': node_port: 30683`. It does not move a number by itself, because that would change a service that is already running. The chance is small: at most 10 workloads can be routed, which is about 1.6% for a collision among 10, and about 0.1% for 10 backends among 50000 priorities.

**The private IP of an instance is not derived.** By default AWS picks a free address of the VPC-B subnet when the instance is created, so two instances cannot collide however many there are (a hash over the 240 usable addresses collides with a 17% chance already at 10 instances). The edge layer reads the real address that the compute layer publishes after the instance exists. Two things follow: the address is only known after `apply`, and **if an instance is replaced it gets a new address**, so the edge layer has to be applied again. `make apply LAYER=compute` and the Apply workflow both continue with the layers after it, so this happens by itself; only `make apply LAYER=compute ONLY=1` leaves it out. Set `private_ip` only when you need a fixed address. The network layer resolves everything once and publishes it as its `workloads`, `instances` and `backends` outputs; the other layers read those.

**Limit on backends that point to workloads:** every such backend gets its own target group on the Auto Scaling group of the EKS node group, and an Auto Scaling group can be attached to 10 target groups by default (AWS Service Quotas). So at most 10 backends can point to workloads, and two backends that point to the same workload count twice. `plan` fails with a clear message when there are more, instead of the apply failing in AWS. If you have raised the quota, raise `max_asg_target_groups` in `layers/network/backends.tf`.

## EC2 image templates

An instance cannot choose its own AMI or boot script. It must name an image template that the platform team provides in `templates/ec2/templates.yaml`:

```yaml
nginx-demo:
  description: Amazon Linux 2023 with Nginx serving the demo page
  ami_name_pattern: al2023-ami-2023.*-x86_64
  ami_owners: [amazon]
  user_data_file: nginx-demo.sh.tftpl     # next to templates.yaml
  root_volume_size: 8
  root_volume_type: gp3
```

A template says which image to start from (the most recent AMI that matches) and what to run at boot. The user data file is a `templatefile()` template and receives `http_port`, `paths` (the URL paths routed to the instance) and `page_html`. The generic `ec2-instance` module requires an `image_template`; it does not know what runs on the instance. `plan` fails when an instance has no `template` or names one that does not exist.

To add a template, the platform team adds an entry to `templates.yaml` and the user data file; no Terraform change is needed unless the template needs variables other than the three above.

**Variables**

| Layer | Variable | Default | Description |
|---|---|---|---|
| `compute` | `eks_admin_principal_arns` | `[]` | IAM users/roles with cluster-admin on EKS for local runs (the CI apply role is added automatically) |
| `compute` | `ci_plan_role_arn` | `""` | CI plan role (read-only EKS access). Set by CI from the `AWS_PLAN_ROLE_ARN` secret |
| `compute` | `ci_apply_role_arn` | `""` | CI apply role (EKS admin). Set by CI from the `AWS_APPLY_ROLE_ARN` secret |
| `edge` | `domain_name` | `""` | Existing public Route 53 hosted zone, e.g. `example.com`. Empty = no DNS record; use the NLB DNS name |
| `edge` | `record_name` | `demo` | Subdomain for the demo (`demo.example.com`). Only used when `domain_name` is set |

`domain_name` is optional. Set it to create the Route 53 alias record; leave it empty to skip DNS.

## Environments

The Terraform code of the layers lives once, in `layers/`. An environment is a folder under `envs/` that contains only a `values.yaml`:

```bash
cp -r envs/demo envs/staging        # then edit envs/staging/values.yaml
make plan ENV=staging LAYER=network
make apply-all ENV=staging
```

Change at least `common.name`, the VPC CIDRs and the `Environment` tag; the state bucket can stay the same, because the state key contains the environment name. `scripts/tf.sh <environment> <layer> <terraform args>` is the single entry point (the Makefile and the workflows use it): it sets `TF_VAR_environment`, passes the backend settings on `init`, and keeps one `.terraform` directory per environment and layer in `.terraform-data/`, so switching environments never reuses the wrong backend.

In CI, `terraform-plan.yml` plans every folder under `envs/`, and apply and destroy take the environment name as an input.
