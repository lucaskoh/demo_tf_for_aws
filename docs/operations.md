# Operations

Day-to-day commands, how to check a deployment, what it costs and how to tear it down.

## Makefile shortcuts

The Makefile wraps the common commands. Run `make help` to list them. The environment defaults to `ENV=demo` (a folder under `envs/`). Single-layer targets take `LAYER=network|compute|workloads|edge`.

| Command | What it does |
|---|---|
| `make bootstrap GITHUB_REPO=owner/repo` | One time: create the state bucket and CI roles |
| `make fmt` / `make fmt-check` | Format Terraform files / check formatting (same as CI) |
| `make validate-values` | Check every `envs/*/values.yaml` and the EC2 templates against their JSON Schema |
| `make test-schemas` | Run the schema fixtures in `schemas/tests` |
| `make test-modules` | Run the `terraform test` suites of the modules (`modules/*/tests`, today `env-resolver`); plan-only, no AWS credentials |
| `make test-scripts` | Test `scripts/tf.sh`, `scripts/prepare-platform.sh` and `scripts/platform.sh` (platform versions, environment repositories) with a fake `terraform`; no AWS credentials |
| `make check-docs` | Check the links of `README.md` and `docs/*.md`: every file exists and every `#anchor` matches a heading |
| `make validate` | `validate-values`, `test-modules`, `test-scripts` and `check-docs`, then `init -backend=false` and `validate` for every layer; no AWS credentials needed |
| `make lint` | Run `tflint` on all modules |
| `make init LAYER=...` | Initialize one layer with the S3 backend |
| `make plan LAYER=...` | Create an execution plan for one layer, saved as `tfplan` |
| `make apply LAYER=...` | Plan and apply a layer, **then every layer after it** (`compute` continues with `workloads` and `edge`, `network` with all of them, `edge` is only itself). `ONLY=1` applies just that layer |
| `make destroy LAYER=...` | Destroy one layer (asks for confirmation) |
| `make apply-all` | Apply all layers in order (network first) |
| `make destroy-all` | Destroy all layers in reverse order (edge first); asks per layer |
| `make output LAYER=edge` | Show the outputs of a layer (the backend URLs are in `edge`) |
| `make clean` | Remove `.terraform/` caches and saved plans |

## Verify

```bash
# <host> is demo.<your-domain>, or the NLB DNS name if you did not set domain_name
curl http://<host>/html1   # Hello from web (EKS in VPC-A)
curl http://<host>/html2   # Hello from legacy (EC2 in VPC-B via VPC Peering)
curl http://<host>/        # 404 that lists the routes
```

The `edge` layer prints the URL of each backend (keyed by backend name) as an output (`make output LAYER=edge`). With a domain:

```
backend_urls = {
  "ec2-page" = "http://demo.example.com/html2"
  "eks-page" = "http://demo.example.com/html1"
}
```

Without a domain, the host is the NLB DNS name (for example `demo-nlb-1234567890.elb.ap-northeast-1.amazonaws.com`).

## Cost Estimate

Approximate, for `ap-northeast-1`, on-demand and Spot prices at the time of writing. Check the [AWS pricing pages](https://aws.amazon.com/pricing/) for current numbers.

| Resource | Approx. cost |
|---|---|
| EKS control plane | ~US$0.10 / hr |
| ALB | ~US$0.02 / hr + LCU |
| NLB | ~US$0.02 / hr + NLCU |
| EC2 `t3.micro` + EKS `t3.small` Spot | ~US$0.02 / hr |
| Public IPv4 addresses | ~US$0.005 / hr each |
| VPC Peering (same region) | Free (data transfer charges may apply) |
| **Total** | **~US$0.2 / hr, roughly US$0.4 for a 2-hour test** |

Remember to destroy the environment when you are done (the Terraform Destroy workflow, or `make destroy-all`). Setting up an [AWS Budget](https://docs.aws.amazon.com/cost-management/latest/userguide/budgets-managing-costs.html) alert is also recommended.

## Cleanup

**Option A: GitHub Actions (recommended)**

Go to **Actions → Terraform Destroy → Run workflow**, type `destroy`, and approve the `production` deployment.

**Option B: locally**

```bash
make destroy-all   # edge -> workloads -> compute -> network, asks for confirmation per layer
```

**Optional: remove the state bucket and CI roles** (do this last, after the demo environment is destroyed)

```bash
# The bucket is not force-destroyed, so empty it first (including all versions)
cd bootstrap
terraform destroy -var="github_repo=<your-username>/demo_tf_for_aws"
```
