# What runs (workloads on EKS, instances on EC2) and how traffic reaches it
# (backends: a path routed to one workload or one instance), resolved once from
# envs/<environment>/values.yaml.
#
# This is the single source of truth for every number that must be the same in
# several layers: NodePorts, EC2 private IPs and ALB rule priorities. The other
# layers read the result from this layer's `workloads`, `instances` and
# `backends` outputs and never compute it again. Unless set explicitly in
# values.yaml, the numbers are derived from the name with a hash, so adding or
# removing something never changes the numbers of the others. Collisions are
# rejected by the preconditions in main.tf (data.aws_availability_zones.available).
locals {
  # merge(..., {}) turns a missing or empty section into {} whatever shape the entries have
  workloads_raw = merge(try(local.values.workloads, {}), {})
  instances_raw = merge(try(local.values.instances, {}), {})
  backends_raw  = merge(try(local.values.backends, {}), {})

  # Paths routed to each workload / instance
  paths_by_workload = { for w in keys(local.workloads_raw) : w => [for k, b in local.backends_raw : try(b.path, "") if try(b.workload, null) == w] }
  paths_by_instance = { for i in keys(local.instances_raw) : i => [for k, b in local.backends_raw : try(b.path, "") if try(b.instance, null) == i] }

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

  # Nginx instances in VPC-B, each with a fixed private IP inside the subnet (host 10-249)
  instances = {
    for k, i in local.instances_raw : k => {
      instance_type = try(i.instance_type, null) # null = compute.ec2_instance_type
      private_ip    = coalesce(try(i.private_ip, null), cidrhost(local.vpc_b_subnet_cidr, 10 + parseint(substr(md5(k), 0, 4), 16) % 240))
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
      # Port or IP of the target, copied from it for the edge layer
      node_port  = try(local.workloads[b.workload].node_port, null)
      private_ip = try(local.instances[b.instance].private_ip, null)
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

  # ---- checks (used by the preconditions in main.tf) ----------------------

  name_ok = {
    for k in concat(keys(local.workloads), keys(local.instances)) : k => can(regex("^[a-z0-9-]{1,40}$", k))
  }
  bad_names = [for k, ok in local.name_ok : k if !ok]
  # '<name>-<backend>-tg' is a target group name: at most 32 characters
  bad_backend_keys = [
    for k in keys(local.backends) : k
    if !can(regex("^[a-z0-9-]+$", k)) || length("${local.name}-${k}-tg") > 32
  ]

  # A backend needs a path and exactly one existing target
  bad_targets = [
    for k, b in local.backends_raw : k
    if(try(b.workload, null) != null) == (try(b.instance, null) != null)
    || (try(b.workload, null) != null && !contains(keys(local.workloads_raw), try(b.workload, "")))
    || (try(b.instance, null) != null && !contains(keys(local.instances_raw), try(b.instance, "")))
  ]
  bad_paths = [for k, b in local.backends : k if !can(regex("^[A-Za-z0-9._-]+$", b.path))]
  all_paths = [for b in values(local.backends) : b.path]
  dup_paths = distinct([for p in local.all_paths : p if length([for q in local.all_paths : q if q == p]) > 1])

  all_prios = [for b in values(local.backends) : b.priority]
  bad_prios = [for k, b in local.backends : k if b.priority < 1 || b.priority > 50000]
  dup_prios = distinct([for p in local.all_prios : p if length([for q in local.all_prios : q if q == p]) > 1])

  node_ports = [for w in values(local.exposed_workloads) : w.node_port]
  dup_ports  = distinct([for p in local.node_ports : p if length([for q in local.node_ports : q if q == p]) > 1])
  bad_ports = [
    for k, w in local.workloads : k
    if w.container_port < 1 || w.container_port > 65535 || (w.exposed && (w.node_port < 30000 || w.node_port > 32767))
  ]
  # Without an image the built-in Nginx demo page is used, and Nginx listens on 80
  bad_demo_ports = [for k, w in local.workloads : k if w.image == null && w.container_port != 80]
  bad_images     = [for k, w in local.workloads : k if w.image != null && !can(regex("^[A-Za-z0-9][A-Za-z0-9._/:@-]*$", w.image))]
  bad_health = concat(
    [for k, w in local.workloads : k if !startswith(w.health_check_path, "/")],
    [for k, b in local.backends : k if !startswith(b.health_check_path, "/")]
  )

  # Page texts end up in an HTML page (and for instances in user_data), so no markup characters or line breaks
  bad_texts = concat(
    [for k, w in local.workloads : k if !can(regex("^[^<>\"\\n\\r]*$", "${w.page_title}${w.page_heading}"))],
    [for k, i in local.instances : k if !can(regex("^[^<>\"\\n\\r]*$", "${i.page_title}${i.page_heading}"))]
  )

  # Instance IPs: well formed, inside the VPC-B subnet, unique
  ec2_ips        = [for i in values(local.instances) : i.private_ip]
  dup_ips        = distinct([for p in local.ec2_ips : p if length([for q in local.ec2_ips : q if q == p]) > 1])
  malformed_ips  = [for k, i in local.instances : k if !can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}$", i.private_ip))]
  subnet_b_first = sum([for i, o in split(".", cidrhost(local.vpc_b_subnet_cidr, 0)) : tonumber(o) * pow(256, 3 - i)])
  subnet_b_size  = pow(2, 32 - tonumber(split("/", local.vpc_b_subnet_cidr)[1]))
  outside_ips = [
    for k, i in local.instances : k
    if !contains(local.malformed_ips, k) && (
      sum([for n, o in split(".", i.private_ip) : tonumber(o) * pow(256, 3 - n)]) < local.subnet_b_first ||
      sum([for n, o in split(".", i.private_ip) : tonumber(o) * pow(256, 3 - n)]) >= local.subnet_b_first + local.subnet_b_size
    )
  ]
}
