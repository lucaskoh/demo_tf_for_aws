# Architecture details

The diagram and the request flow are in the [README](../README.md#architecture). This page explains the decisions behind them, the network, the security model and the limits.

## Key Design Decisions

| Decision | Why |
|---|---|
| **No NAT Gateway / Transit Gateway** | NAT Gateway and TGW are billed hourly plus per GB. Public subnets with locked-down Security Groups plus VPC Peering (free) keep the demo cheap. |
| **NLB in front of ALB** | Gives a static entry point (L4) while keeping L7 path routing on the ALB. |
| **Internal ALB** | The ALB only has private IPs and is reachable only through the NLB. Set `internal = false` in the `alb` module to make it internet-facing. |
| **ALB with `instance` target for EKS** | The Node Group's Auto Scaling Group is attached directly to the target group. This avoids installing the AWS Load Balancer Controller for a demo. |
| **ALB with `ip` target for EC2** | Allows the ALB in VPC-A to target a private IP in the peered VPC-B. |
| **Spot instances for EKS nodes** | Lowest-cost compute for a short-lived environment. |
| **Layers shared by all environments** | The Terraform code lives once in `layers/`; an environment is a folder with only a `values.yaml`. Adding `staging` means copying that folder and editing the values. |
| **Routes are separate from what runs** | `workloads`, `instances` and `backends` are different sections of `values.yaml`. A backend is only a path that leads to a workload or an instance, so one workload can have several paths, and a workload nobody routes to stays inside the cluster. |
| **Numbers are derived, not chosen** | NodePorts and ALB priorities come from a hash of the name, so adding or removing something never changes the others. EC2 private IPs are not derived at all: AWS picks a free address, so they cannot collide. Security group rules are generated from what is routed. |
| **EC2 instances come from image templates** | An instance names a template from `templates/ec2/` (AMI and boot script) maintained by the platform team; it cannot pick an arbitrary image or script. |

## Network Plan

| Component | CIDR / IP | AZ | Purpose |
|---|---|---|---|
| **VPC-A** | `10.0.0.0/16` | - | Entry layer (NLB, ALB) and EKS |
| ├ `vpc-a-public-1` | `10.0.1.0/24` | 1st AZ of the region | ALB/NLB node, EKS Spot node |
| └ `vpc-a-public-2` | `10.0.2.0/24` | 2nd AZ of the region | ALB/NLB node (ALB requires 2 AZs) |
| **VPC-B** | `10.1.0.0/16` | - | Standalone EC2 workload |
| └ `vpc-b-public-1` | `10.1.1.0/24` | 1st AZ of the region | EC2 instances (AWS picks a free address, or you set one) |
| **VPC Peering** | - | - | A route table: `10.1.0.0/16 → pcx`; B route table: `10.0.0.0/16 → pcx` |

The two CIDR blocks do not overlap, which is required for VPC Peering.

Subnet CIDRs are derived from the VPC CIDRs (`/16` → `/24`). The AZs are the first two available AZs of the region, sorted by name (in `ap-northeast-1` that is `ap-northeast-1a` and `ap-northeast-1c`), so the table stays valid when you change `region`.

## Security Model

EKS nodes and the EC2 instance sit in public subnets (they need outbound internet to pull images and packages without a NAT Gateway). Inbound access is therefore locked down with chained Security Groups so that **the only way in is through the load balancer**.

| Security Group | Attached to | Inbound | Outbound |
|---|---|---|---|
| `alb-sg` | ALB | `0.0.0.0/0` → TCP 80 | EKS nodes (NodePort of each routed workload), `10.1.0.0/16` (when an instance is routed) |
| `eks-node-sg` | EKS worker nodes | **Only** `alb-sg` → the NodePort of each routed workload | All |
| `ec2-sg` | VPC-B EC2 | **Only** `10.0.0.0/16` → TCP 80 | All |

Direct requests to a node's or the EC2 instance's public IP are dropped. The rules are generated from what is routed; nobody writes them by hand.

**Why `alb-sg` accepts `0.0.0.0/0`:** the ALB is internal, so it only has private IP addresses and nothing on the internet can route to it. The only public entry point is the NLB. The rule therefore does not open the ALB to the internet: it only matters for traffic that is already inside VPC-A, or inside VPC-B through the peering. It is not limited to the VPC CIDR because the source address that the ALB sees when the NLB forwards to it (the NLB's own address or the original client's) has not been verified in this project; limiting it is a possible hardening step once that has been tested.

## Limitations

This project is a **learning / demo environment**, not a production blueprint.

- **HTTP only.** To enable HTTPS, add an ACM certificate and a port 443 listener to the ALB.
- **Public EKS API endpoint.** By default it accepts connections from `0.0.0.0/0`. Every request still needs an IAM identity that has an EKS access entry (the cluster uses access entries only, and the creator does not get admin rights automatically), so an open endpoint is not an open cluster, but it is a larger attack surface than necessary. It is open because the `workloads` layer talks to the Kubernetes API from the CI runner, and the addresses of GitHub-hosted runners are many and change. To narrow it, set `compute.eks.public_access_cidrs` in `values.yaml`. That locks out the GitHub-hosted runners too, so combine it with a self-hosted runner inside an allowed range, or with a private endpoint (`endpoint_private_access` of the `eks` module) and a runner that can reach the VPC. None of that is set up here.
- **Public subnets for compute.** Chosen to avoid NAT Gateway cost. Production workloads should use private subnets.
- **Public S3 bucket** for demo images. For production, use CloudFront with Origin Access Control.
- **Spot nodes** can be reclaimed at any time.
- **EC2 instances live in one subnet, so in one AZ.** No high availability for the instances.
- **Only Deployments.** There is no StatefulSet, because the cluster has no EBS CSI driver (no persistent volumes).
- **No allowlist for container images yet.** A workload can use any public image; restricting that is part of the planned guardrails.
- **Broad CI permissions.** The apply role uses `AdministratorAccess` for simplicity (only jobs approved in the `production` environment can assume it). See [From demo to production: the apply role](ci-cd.md#from-demo-to-production-the-apply-role).
