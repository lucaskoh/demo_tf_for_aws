# Team guide: from a YAML file to a deployment

For someone who wants to run something on the platform and has not used this repository before. You edit **YAML files**; you do not write Terraform. This page follows one change from start to finish. The [configuration reference](configuration.md) lists every field.

## What you own, and what you do not

| You | The platform team |
|---|---|
| Your app files: `envs/<environment>/apps/` (a file or a folder per team) | `envs/<environment>/values.yaml` (network, EKS size, allowed images, ...), `layers/`, `modules/`, `templates/`, the pipelines |

An app file describes three things: **workloads** (a container on the EKS cluster), **instances** (a virtual machine from a platform image template) and **backends** (a URL path that leads to one of them). Everything else is derived: security group rules, NodePorts, load balancer rules.

## 1. Add a file

Create `envs/demo/apps/shop.yaml` (the name is yours; any `*.yaml` file under `apps/` is read, also in sub-folders):

```yaml
# yaml-language-server: $schema=../../../schemas/apps.schema.json
workloads:
  shop:
    image: ghcr.io/your-org/shop:1.4.0     # leave out to get the built-in demo page
    container_port: 8080
    health_check_path: /healthz

backends:
  shop-page:
    path: shop                              # served at /shop
    workload: shop
```

- The first line gives your editor completion and error underlines (VS Code with the YAML extension).
- A name (workload, instance or backend) may exist **once in the whole environment**, across all files.
- A workload that no backend points to is only reachable inside the cluster.
- Two things are checked before anything is deployed: the image must be allowed (`allowed_images`, if the platform set it), and a backend needs exactly one target.

Optionally check it on your machine: `make validate-values` (needs `python3 -m pip install -r scripts/requirements.txt`).

## 2. Open a pull request

Push a branch and open a pull request to `main`. Two checks run, and both must pass:

- **validate** checks the schema, the rules and the formatting. A mistake shows up as an annotation on the changed line, for example `envs/demo/apps/shop.yaml:5: workloads.shop: unknown key 'replica' - did you mean 'replicas'?`.
- **plan** posts one comment with the Terraform plan of every layer of every environment: what would be created, changed or destroyed. Read it: your change should add the Deployment and Service (`workloads`), the target group and the rule (`edge`) and the security group rules (`network`). A layer shows *skipped* when the layers before it are not deployed yet; that is normal for an environment that does not exist yet.

The platform owner is asked to review (see `.github/CODEOWNERS`). **Merging does not deploy anything.**

## 3. Deploy

After the merge, the platform owner (or you, if you may) runs **Actions → Terraform Apply → Run workflow** with `env_name` set to the environment (`demo`). It must run from `main` and needs the approval of a reviewer in the `production` environment of GitHub. It applies the four layers in order (`network`, `compute`, `workloads`, `edge`) and prints the URLs of the backends at the end:

```
backend_urls = { "shop-page" = "http://<load-balancer-name>/shop", ... }
```

Give it a minute or two: right after an apply the EKS node can still be registering in the target group, and the page answers `502` or times out until it is healthy.

## 4. Check, change, remove

- **Check:** open the URL. The default answer for any other path is a `404` that lists the routes.
- **Change:** edit the file and repeat from step 2. Changing an image or replicas updates the Deployment in place.
- **Renaming is not a change.** The NodePort and the load balancer priority are derived from the name, so a new name replaces the resources and the traffic to them stops while that happens. Add the new one, move the traffic, then remove the old one.
- **Remove:** delete the entries and repeat from step 2; the platform removes what it created for them.
- **Destroy a whole environment:** **Actions → Terraform Destroy**, type `destroy` (a manual step with its own approval).

## Errors you will meet

| Message | What to do |
|---|---|
| `unknown key 'x' - did you mean 'y'?` | A misspelled field; the schema lists the valid ones. |
| `A name may be defined once in the whole environment, but workload 'shop' is defined in apps/a.yaml and apps/b.yaml` | Rename one, or remove the duplicate. |
| `Each backend needs a path and exactly one target ...` | A backend points to no workload or instance, to two, or to one that does not exist. |
| `Two workloads got the same NodePort ... a free value is suggested: workload 'x': node_port: 30683` | A hash collision (rare). Set the suggested `node_port` on that workload. The same for `priority` on a backend. |
| `Images must come from a repository in common.allowed_images ...` | Use an allowed image, or ask the platform team to add your repository. |
| `Every instance needs 'template: <name>' ...` | An instance must name an image template from `templates/ec2/templates.yaml`; the message lists them. |
| `N backends point to workloads, but an Auto Scaling group can be attached to 10 target groups` | A platform limit; ask the platform team. |

## Where to read more

[Configuration](configuration.md) for every field, [CI/CD](ci-cd.md) for what the pipelines do and how they are secured, [Architecture](architecture.md) for the design decisions and the limits, [Operations](operations.md) for the commands and the cost (about US$0.2 per hour while an environment runs; destroy it when you are done).
