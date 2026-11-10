# The rules. Each one is a condition and the message that explains it, side by side; `problems`
# (the output) lists the messages of the rules that fail, so every problem is reported at once.
# Adding a rule = one entry in local.rules + one test in tests/checks.tftest.hcl.
locals {
  # ---- facts the rules use ------------------------------------------------------

  # Where every name is defined, to report a name that is defined twice
  app_sections = { workload = "workloads", instance = "instances", backend = "backends" }
  app_entries = flatten([
    for f, a in local.apps : [
      for kind, section in local.app_sections : [
        for name in keys(merge(try(a[section], {}), {})) : { file = f, kind = kind, name = name }
      ]
    ]
  ])
  duplicate_names = {
    for key in distinct([for e in local.app_entries : "${e.kind} '${e.name}'"]) :
    key => [for e in local.app_entries : "apps/${e.file}" if "${e.kind} '${e.name}'" == key]
    if length([for e in local.app_entries : e if "${e.kind} '${e.name}'" == key]) > 1
  }
  duplicate_messages = [for key, files in local.duplicate_names : "${key} is defined in ${join(" and ", files)}"]

  # The old layout kept these sections in values.yaml; they are not read from there any more
  sections_in_values = [for s in values(local.app_sections) : s if contains(var.platform_sections, s)]

  # Every backend that points to a workload gets its own target group on the Auto Scaling group of
  # the EKS node group, and an Auto Scaling group can be attached to 10 target groups by default
  # (Service Quotas). Raise the number if you have raised the quota.
  workload_backend_count = length([for b in values(local.backends) : b if b.workload != null])

  name_ok = {
    for k in concat(keys(local.workloads), keys(local.instances)) : k => can(regex("^[a-z0-9-]{1,40}$", k))
  }
  bad_names = [for k, ok in local.name_ok : k if !ok]
  # '<name>-<backend>-tg' is a target group name: at most 32 characters
  bad_backend_keys = [
    for k in keys(local.backends) : k
    if !can(regex("^[a-z0-9-]+$", k)) || length("${var.name}-${k}-tg") > 32
  ]

  # Every instance must name an image template that the platform provides
  bad_templates = [for k, i in local.instances : k if i.template == null || !contains(var.ec2_template_names, coalesce(i.template, ""))]

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

  # Same idea as node_port_fixes, for the ALB rule priority
  priority_fixes = flatten([
    for p in local.dup_prios : [
      for k in slice(sort([for k, b in local.backends : k if b.priority == p]), 1, length([for k, b in local.backends : k if b.priority == p])) :
      "backend '${k}': priority: ${[for n in range(1, 1001) : 1 + (parseint(substr(md5(k), 0, 5), 16) + n) % 49999 if !contains(local.all_prios, 1 + (parseint(substr(md5(k), 0, 5), 16) + n) % 49999)][0]}"
    ]
  ])

  node_ports = [for w in values(local.exposed_workloads) : w.node_port]
  dup_ports  = distinct([for p in local.node_ports : p if length([for q in local.node_ports : q if q == p]) > 1])

  # When two entries get the same number, the first one by name keeps it and each of the others needs a
  # new one. The message offers a free value for each, found by stepping on from the hash of its name
  # (range() is limited to 1024 values; at most a few dozen numbers are in use, so 1000 candidates are plenty).
  # (Failing loudly is deliberate: moving a number by itself would change a service that is already running.)
  node_port_fixes = flatten([
    for p in local.dup_ports : [
      for k in slice(sort([for k, w in local.exposed_workloads : k if w.node_port == p]), 1, length([for k, w in local.exposed_workloads : k if w.node_port == p])) :
      "workload '${k}': node_port: ${[for n in range(1, 1001) : 30000 + (parseint(substr(md5(k), 0, 6), 16) + n) % 2768 if !contains(local.node_ports, 30000 + (parseint(substr(md5(k), 0, 6), 16) + n) % 2768)][0]}"
    ]
  ])
  bad_ports = [
    for k, w in local.workloads : k
    if w.container_port < 1 || w.container_port > 65535 || (w.exposed ? (w.node_port < 30000 || w.node_port > 32767) : false)
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

  # Instance IPs: only the ones that are set explicitly are checked (well formed, inside the VPC-B subnet,
  # unique). The others are chosen by AWS.
  fixed_ip_instances = { for k, i in local.instances : k => i if i.private_ip != null }
  fixed_ips          = [for i in values(local.fixed_ip_instances) : i.private_ip]
  dup_ips            = distinct([for p in local.fixed_ips : p if length([for q in local.fixed_ips : q if q == p]) > 1])
  malformed_ips      = [for k, i in local.fixed_ip_instances : k if !can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}$", i.private_ip))]
  subnet_b_first     = sum([for i, o in split(".", cidrhost(var.vpc_b_subnet_cidr, 0)) : tonumber(o) * pow(256, 3 - i)])
  subnet_b_size      = pow(2, 32 - tonumber(split("/", var.vpc_b_subnet_cidr)[1]))
  # (only well formed addresses are converted to numbers, the conversion fails for the others)
  ip_numbers = {
    for k, i in local.fixed_ip_instances : k => sum([for n, o in split(".", i.private_ip) : tonumber(o) * pow(256, 3 - n)])
    if !contains(local.malformed_ips, k)
  }
  outside_ips = [
    for k, n in local.ip_numbers : k
    if n < local.subnet_b_first || n >= local.subnet_b_first + local.subnet_b_size
  ]

  # ---- the rules ------------------------------------------------------------------

  rules = [
    {
      failed  = length(local.sections_in_values) > 0
      message = "values.yaml is the platform file and does not declare ${join(", ", local.sections_in_values)} any more. Move them to a file in envs/<environment>/apps/."
    },
    {
      failed  = length(local.ignored_app_files) > 0
      message = "Only files that end in .yaml are read from envs/<environment>/apps/. These are ignored: ${join(", ", local.ignored_app_files)}. Rename them."
    },
    {
      failed  = length(local.duplicate_names) > 0
      message = "A name may be defined once in the whole environment, but ${join("; ", local.duplicate_messages)}."
    },
    {
      failed  = length(local.backends) == 0
      message = "The files in envs/<environment>/apps/ must declare at least one backend under backends:."
    },
    {
      failed  = length(local.bad_names) > 0 || length(local.bad_backend_keys) > 0
      message = "Names under workloads:, instances: and backends: must be lowercase letters, digits and hyphens (workloads and instances up to 40 characters), and '${var.name}-<backend>-tg' must be at most 32 characters (target group name limit). Rename: ${join(", ", concat(local.bad_names, local.bad_backend_keys))}."
    },
    {
      failed  = local.workload_backend_count > var.max_asg_target_groups
      message = "${local.workload_backend_count} backends point to workloads, but an Auto Scaling group can be attached to ${var.max_asg_target_groups} target groups by default (two backends that point to the same workload count twice). Remove backends, or raise max_asg_target_groups in layers/network/backends.tf after you have raised the Service Quotas limit."
    },
    {
      failed  = length(local.bad_templates) > 0
      message = "Every instance needs 'template: <name>' with a template from templates/ec2/templates.yaml (${join(", ", var.ec2_template_names)}). Check: ${join(", ", local.bad_templates)}."
    },
    {
      failed  = length(local.bad_targets) > 0
      message = "Each backend needs a path and exactly one target, either 'workload: <name>' or 'instance: <name>', that is declared under workloads: or instances:. Check: ${join(", ", local.bad_targets)}."
    },
    {
      failed  = length(local.bad_paths) > 0
      message = "path of a backend may contain only letters, digits, dots, underscores and hyphens (one URL segment, no slashes). Check: ${join(", ", local.bad_paths)}."
    },
    {
      failed  = length(local.dup_paths) > 0
      message = "Backends must use different paths. Used more than once: ${join(", ", local.dup_paths)}."
    },
    {
      failed  = length(local.bad_prios) > 0 || length(local.dup_prios) > 0
      message = "ALB rule priorities must be between 1 and 50000 and unique. ${length(local.dup_prios) > 0 ? "Two backends got the same priority, which can happen by chance. Set one of these (a free value is suggested): ${join("; ", local.priority_fixes)}. " : ""}${length(local.bad_prios) > 0 ? "Out of range: ${join(", ", local.bad_prios)}." : ""}"
    },
    {
      failed  = length(local.bad_ports) > 0 || length(local.dup_ports) > 0
      message = "A routed workload needs a unique node_port between 30000 and 32767, and container_port must be between 1 and 65535. ${length(local.dup_ports) > 0 ? "Two workloads got the same NodePort, which can happen by chance. Set one of these (a free value is suggested): ${join("; ", local.node_port_fixes)}. " : ""}${length(local.bad_ports) > 0 ? "Check: ${join(", ", local.bad_ports)}." : ""}"
    },
    {
      failed  = length(local.bad_demo_ports) > 0
      message = "A workload without 'image' serves the built-in Nginx demo page, which listens on port 80. Remove container_port or set an image: ${join(", ", local.bad_demo_ports)}."
    },
    {
      failed  = length(local.malformed_ips) > 0 || length(local.outside_ips) > 0 || length(local.dup_ips) > 0
      message = "A private_ip that is set on an instance must be unique and inside the VPC-B subnet ${var.vpc_b_subnet_cidr}. Leave private_ip out to let AWS choose a free address. Check: ${join(", ", concat(local.malformed_ips, local.outside_ips, [for k, i in local.fixed_ip_instances : k if contains(local.dup_ips, i.private_ip)]))}."
    },
    {
      failed  = length(local.bad_texts) > 0
      message = "page_title and page_heading must not contain <, > or \" characters or line breaks. Check: ${join(", ", local.bad_texts)}."
    },
    {
      failed  = length(local.bad_images) > 0 || length(local.bad_health) > 0
      message = "image must look like an image reference (for example nginx:1.27-alpine) and health_check_path must start with '/'. Check: ${join(", ", concat(local.bad_images, local.bad_health))}."
    },
  ]

  problems = [for r in local.rules : r.message if r.failed]
}
