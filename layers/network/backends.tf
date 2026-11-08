# The backends declared in envs/<environment>/values.yaml, resolved once.
#
# This is the single source of truth for every number that must be the same in
# several layers: NodePorts, EC2 private IPs and ALB rule priorities. The other
# layers read the result from this layer's `backends` output and never compute
# it again. Unless set explicitly in values.yaml, the numbers are derived from
# the backend name with a hash, so adding or removing a backend never changes
# the numbers of the others. Collisions are rejected by the preconditions in
# main.tf (data.aws_availability_zones.available).
locals {
  backends_raw = local.values.backends

  backends = {
    for k, b in local.backends_raw : k => {
      type = b.type
      path = b.path

      # ALB rule priority (1-50000), unique per listener
      priority = coalesce(try(b.priority, null), 1 + parseint(substr(md5(k), 0, 5), 16) % 49999)

      # eks backends: NodePort on the worker nodes (30000-32767)
      node_port = b.type == "eks" ? coalesce(try(b.node_port, null), 30000 + parseint(substr(md5(k), 0, 6), 16) % 2768) : null

      # ec2 backends: fixed private IP inside the VPC-B subnet (host 10-249)
      private_ip = b.type == "ec2" ? coalesce(try(b.private_ip, null), cidrhost(local.vpc_b_subnet_cidr, 10 + parseint(substr(md5(k), 0, 4), 16) % 240)) : null
      # null = compute.ec2_instance_type
      instance_type = b.type == "ec2" ? try(b.instance_type, null) : null

      # eks backends: null image = the built-in demo page served by Nginx
      image          = b.type == "eks" ? try(b.image, null) : null
      container_port = b.type == "eks" ? coalesce(try(b.container_port, null), 80) : null
      replicas       = b.type == "eks" ? coalesce(try(b.replicas, null), 1) : null

      # Path the ALB and Kubernetes use for health checks. The demo page lives at /<path>/index.html.
      health_check_path = coalesce(
        try(b.health_check_path, null),
        b.type == "eks" && try(b.image, null) != null ? "/" : "/${b.path}/index.html"
      )

      page_title = coalesce(try(b.page_title, null), upper(b.type))
      page_heading = coalesce(
        try(b.page_heading, null),
        "Hello from ${k} (${b.type == "eks" ? "EKS in VPC-A" : "EC2 in VPC-B via VPC Peering"})"
      )
    }
  }

  eks_backends = { for k, b in local.backends : k => b if b.type == "eks" }
  ec2_backends = { for k, b in local.backends : k => b if b.type == "ec2" }

  # ---- checks (used by the preconditions in main.tf) ----------------------

  backend_types_ok = alltrue([for b in values(local.backends) : contains(["eks", "ec2"], b.type)])

  bad_keys = [
    for k in keys(local.backends) : k
    if !can(regex("^[a-z0-9-]+$", k)) || length("${local.name}-${k}-tg") > 32
  ]
  bad_paths = [for k, b in local.backends : k if !can(regex("^[A-Za-z0-9._-]+$", b.path))]

  all_paths  = [for b in values(local.backends) : b.path]
  dup_paths  = distinct([for p in local.all_paths : p if length([for q in local.all_paths : q if q == p]) > 1])
  dup_prios  = distinct([for p in [for b in values(local.backends) : b.priority] : p if length([for q in values(local.backends) : q if q.priority == p]) > 1])
  bad_prios  = [for k, b in local.backends : k if b.priority < 1 || b.priority > 50000]
  node_ports = [for b in values(local.eks_backends) : b.node_port]
  dup_ports  = distinct([for p in local.node_ports : p if length([for q in local.node_ports : q if q == p]) > 1])
  bad_ports  = [for k, b in local.eks_backends : k if b.node_port < 30000 || b.node_port > 32767 || b.container_port < 1 || b.container_port > 65535]
  # Without an image the built-in Nginx demo page is used, and Nginx listens on 80
  bad_demo_ports = [for k, b in local.eks_backends : k if b.image == null && b.container_port != 80]
  bad_images     = [for k, b in local.eks_backends : k if b.image != null && !can(regex("^[A-Za-z0-9][A-Za-z0-9._/:@-]*$", b.image))]
  # Page texts end up in an HTML page (and for ec2 in user_data), so no markup characters or line breaks
  bad_texts  = [for k, b in local.backends : k if !can(regex("^[^<>\"\\n\\r]*$", "${b.page_title}${b.page_heading}"))]
  bad_health = [for k, b in local.backends : k if !startswith(b.health_check_path, "/")]

  # EC2 IPs: well formed, inside the VPC-B subnet, unique
  ec2_ips        = [for b in values(local.ec2_backends) : b.private_ip]
  dup_ips        = distinct([for p in local.ec2_ips : p if length([for q in local.ec2_ips : q if q == p]) > 1])
  malformed_ips  = [for k, b in local.ec2_backends : k if !can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}$", b.private_ip))]
  subnet_b_first = sum([for i, o in split(".", cidrhost(local.vpc_b_subnet_cidr, 0)) : tonumber(o) * pow(256, 3 - i)])
  subnet_b_size  = pow(2, 32 - tonumber(split("/", local.vpc_b_subnet_cidr)[1]))
  outside_ips = [
    for k, b in local.ec2_backends : k
    if !contains(local.malformed_ips, k) && (
      sum([for i, o in split(".", b.private_ip) : tonumber(o) * pow(256, 3 - i)]) < local.subnet_b_first ||
      sum([for i, o in split(".", b.private_ip) : tonumber(o) * pow(256, 3 - i)]) >= local.subnet_b_first + local.subnet_b_size
    )
  ]
}
