# Turns the app files of an environment (workloads, instances, backends) into the resolved
# values the layers use: defaults filled in, and the numbers that must be the same in several
# layers (NodePort, ALB rule priority) derived from the name with a hash, so adding or removing
# something never changes the numbers of the others.
#
# The module has no resources and never fails: the rules are in checks.tf and the ones that
# fail are listed in the `problems` output. The caller decides what to do with them. Tests:
# `make test-modules` (tests/*.tftest.hcl).
locals {
  # ---- the app files --------------------------------------------------------
  # Any number of files, also in sub-folders (for example one folder per team). They are merged
  # as a union: a name that two files define is a problem, and nothing is overridden.
  from_text = var.app_sources != null

  # Sorted, so that the result and the messages do not depend on the order the files are listed in
  all_files = local.from_text ? sort(keys(var.app_sources)) : sort(tolist(fileset(var.apps_dir, "**")))
  # Files that are not read because of their name (.yml, .yaml.bak, ...): reported, never ignored silently
  ignored_app_files = [for f in local.all_files : f if !endswith(f, ".yaml")]
  app_files         = [for f in local.all_files : f if endswith(f, ".yaml")]

  apps = {
    for f in local.app_files :
    f => yamldecode(local.from_text ? var.app_sources[f] : file("${var.apps_dir}/${f}"))
  }

  # merge(..., {}) turns a missing or empty section into {} whatever shape the entries have
  workloads_raw = merge([for f, a in local.apps : merge(try(a.workloads, {}), {})]...)
  instances_raw = merge([for f, a in local.apps : merge(try(a.instances, {}), {})]...)
  backends_raw  = merge([for f, a in local.apps : merge(try(a.backends, {}), {})]...)

  # Paths routed to each workload / instance
  paths_by_workload = { for w in keys(local.workloads_raw) : w => [for k, b in local.backends_raw : try(b.path, "") if try(b.workload, null) == w] }
  paths_by_instance = { for i in keys(local.instances_raw) : i => [for k, b in local.backends_raw : try(b.path, "") if try(b.instance, null) == i] }

  # ---- resolved ---------------------------------------------------------------

  # Deployments on the EKS cluster. Only workloads that are routed to get a NodePort
  # (and security group rules); the others are only reachable inside the cluster.
  workloads = {
    for k, w in local.workloads_raw : k => {
      # null image = the built-in Nginx demo page
      image             = try(w.image, null)
      container_port    = coalesce(try(w.container_port, null), 80)
      replicas          = coalesce(try(w.replicas, null), 1)
      health_check_path = coalesce(try(w.health_check_path, null), "/")
      paths             = local.paths_by_workload[k]
      exposed           = length(local.paths_by_workload[k]) > 0
      node_port         = length(local.paths_by_workload[k]) > 0 ? coalesce(try(w.node_port, null), 30000 + parseint(substr(md5(k), 0, 6), 16) % 2768) : null
      page_title        = coalesce(try(w.page_title, null), "EKS")
      page_heading      = coalesce(try(w.page_heading, null), "Hello from ${k} (EKS in VPC-A)")
    }
  }

  # Nginx instances in VPC-B; the private IP is chosen by AWS unless it is set
  instances = {
    for k, i in local.instances_raw : k => {
      template      = try(i.template, null)
      instance_type = try(i.instance_type, null) # null = compute.ec2_instance_type
      private_ip    = try(i.private_ip, null)    # null = chosen by AWS
      paths         = local.paths_by_instance[k]
      page_title    = coalesce(try(i.page_title, null), "EC2")
      page_heading  = coalesce(try(i.page_heading, null), "Hello from ${k} (EC2 in VPC-B via VPC Peering)")
    }
  }

  # Routes: a path on the ALB that leads to one workload or one instance
  backends = {
    for k, b in local.backends_raw : k => {
      path     = try(b.path, "")
      workload = try(b.workload, null)
      instance = try(b.instance, null)
      # ALB rule priority (1-50000), unique per listener
      priority = coalesce(try(b.priority, null), 1 + parseint(substr(md5(k), 0, 5), 16) % 49999)
      # NodePort of the target workload, copied from it for the edge layer
      node_port = try(local.workloads[b.workload].node_port, null)
      # The demo page lives at /<path>/index.html; a custom image is checked at the
      # health_check_path of its workload (default /)
      health_check_path = coalesce(
        try(b.health_check_path, null),
        try(local.workloads[b.workload].image, null) != null ? local.workloads[b.workload].health_check_path : "/${try(b.path, "")}/index.html"
      )
    }
  }

  exposed_workloads = { for k, w in local.workloads : k => w if w.exposed }
  routed_instances  = { for k, i in local.instances : k => i if length(i.paths) > 0 }
}
