# Defaults, what is exposed or routed, and the derived numbers.
#
# The golden values (NodePort 31685, priorities 9973 and 38736) are derived from the names with a
# hash. If one of these tests fails after a change, the change moves the NodePort or the ALB
# priority of services that may already be running: that needs a deliberate decision.

variables {
  name               = "demo"
  vpc_b_subnet_cidr  = "10.1.1.0/24"
  ec2_template_names = ["nginx-demo"]
}

run "demo_environment_golden_values" {
  command = plan
  variables {
    app_sources = {
      "demo.yaml" = jsonencode({
        workloads = { web = {} }
        instances = { legacy = { template = "nginx-demo" } }
        backends = {
          "eks-page" = { path = "html1", workload = "web" }
          "ec2-page" = { path = "html2", instance = "legacy" }
        }
      })
    }
  }

  assert {
    condition     = output.workloads["web"].node_port == 31685
    error_message = "NodePort of 'web' changed: ${output.workloads["web"].node_port}"
  }
  assert {
    condition     = output.backends["eks-page"].priority == 9973 && output.backends["ec2-page"].priority == 38736
    error_message = "ALB priority changed: ${jsonencode({ for k, b in output.backends : k => b.priority })}"
  }
  assert {
    condition     = output.backends["eks-page"].node_port == 31685 && output.backends["ec2-page"].node_port == null
    error_message = "A backend must copy the NodePort of its workload (and only a workload has one)"
  }
  assert {
    condition     = length(output.problems) == 0
    error_message = "The demo environment must be valid: ${jsonencode(output.problems)}"
  }
}

run "defaults" {
  command = plan
  variables {
    app_sources = {
      "a.yaml" = jsonencode({
        workloads = { web = {} }
        instances = { box = { template = "nginx-demo" } }
        backends = {
          home = { path = "home", workload = "web" }
          old  = { path = "old", instance = "box" }
        }
      })
    }
  }

  assert {
    condition = (
      output.workloads["web"].image == null &&
      output.workloads["web"].container_port == 80 &&
      output.workloads["web"].replicas == 1 &&
      output.workloads["web"].health_check_path == "/" &&
      output.workloads["web"].page_title == "EKS" &&
      output.workloads["web"].page_heading == "Hello from web (EKS in VPC-A)"
    )
    error_message = "Workload defaults changed: ${jsonencode(output.workloads["web"])}"
  }
  assert {
    condition = (
      output.instances["box"].private_ip == null &&
      output.instances["box"].instance_type == null &&
      output.instances["box"].page_title == "EC2" &&
      output.instances["box"].page_heading == "Hello from box (EC2 in VPC-B via VPC Peering)"
    )
    error_message = "Instance defaults changed (the private IP is chosen by AWS unless set): ${jsonencode(output.instances["box"])}"
  }
  assert {
    condition     = jsonencode(output.workloads["web"].paths) == "[\"home\"]" && jsonencode(output.instances["box"].paths) == "[\"old\"]"
    error_message = "Each workload and instance must list the paths routed to it"
  }
}

run "only_routed_things_are_exposed" {
  command = plan
  variables {
    app_sources = {
      "a.yaml" = jsonencode({
        workloads = { web = {}, worker = {} }
        instances = { box = { template = "nginx-demo" }, spare = { template = "nginx-demo" } }
        backends = {
          home = { path = "home", workload = "web" }
          old  = { path = "old", instance = "box" }
        }
      })
    }
  }

  assert {
    condition     = jsonencode(keys(output.exposed_workloads)) == "[\"web\"]" && jsonencode(keys(output.routed_instances)) == "[\"box\"]"
    error_message = "exposed_workloads: ${jsonencode(keys(output.exposed_workloads))}, routed_instances: ${jsonencode(keys(output.routed_instances))}"
  }
  assert {
    condition     = output.workloads["worker"].exposed == false && output.workloads["worker"].node_port == null
    error_message = "A workload nobody routes to is a ClusterIP Service and gets no NodePort"
  }
  assert {
    condition     = length(output.problems) == 0
    error_message = "Unexpected problems: ${jsonencode(output.problems)}"
  }
}

run "explicit_values_win_over_derived_ones" {
  command = plan
  variables {
    app_sources = {
      "a.yaml" = jsonencode({
        workloads = { web = { node_port = 31000, replicas = 3, page_heading = "Custom" } }
        instances = { box = { template = "nginx-demo", private_ip = "10.1.1.50", instance_type = "t3.small" } }
        backends = {
          home = { path = "home", workload = "web", priority = 42 }
          old  = { path = "old", instance = "box" }
        }
      })
    }
  }

  assert {
    condition     = output.workloads["web"].node_port == 31000 && output.backends["home"].node_port == 31000
    error_message = "An explicit node_port must be used by the workload and copied to its backend"
  }
  assert {
    condition     = output.backends["home"].priority == 42
    error_message = "An explicit priority must be used"
  }
  assert {
    condition     = output.workloads["web"].replicas == 3 && output.workloads["web"].page_heading == "Custom"
    error_message = "Explicit workload values must be used: ${jsonencode(output.workloads["web"])}"
  }
  assert {
    condition     = output.instances["box"].private_ip == "10.1.1.50" && output.instances["box"].instance_type == "t3.small"
    error_message = "Explicit instance values must be used: ${jsonencode(output.instances["box"])}"
  }
  assert {
    condition     = length(output.problems) == 0
    error_message = "Unexpected problems: ${jsonencode(output.problems)}"
  }
}

run "health_check_paths" {
  command = plan
  variables {
    app_sources = {
      "a.yaml" = jsonencode({
        workloads = {
          demo   = {}
          custom = { image = "nginx:1.27-alpine", health_check_path = "/healthz" }
          plain  = { image = "nginx:1.27-alpine" }
        }
        instances = { box = { template = "nginx-demo" } }
        backends = {
          a = { path = "a", workload = "demo" }
          b = { path = "b", workload = "custom" }
          c = { path = "c", workload = "plain" }
          d = { path = "d", workload = "custom", health_check_path = "/ping" }
          e = { path = "e", instance = "box" }
        }
      })
    }
  }

  assert {
    condition     = output.backends["a"].health_check_path == "/a/index.html"
    error_message = "The demo page is checked at /<path>/index.html: ${output.backends["a"].health_check_path}"
  }
  assert {
    condition     = output.backends["b"].health_check_path == "/healthz" && output.backends["c"].health_check_path == "/"
    error_message = "A custom image is checked at the health_check_path of its workload (default /)"
  }
  assert {
    condition     = output.backends["d"].health_check_path == "/ping"
    error_message = "A health_check_path on the backend wins"
  }
  assert {
    condition     = output.backends["e"].health_check_path == "/e/index.html"
    error_message = "An instance serves the demo page too: ${output.backends["e"].health_check_path}"
  }
}

run "node_port_stays_in_range" {
  command = plan
  variables {
    app_sources = {
      "a.yaml" = jsonencode({
        workloads = { for i in range(8) : "w${i}" => {} }
        backends  = { for i in range(8) : "b${i}" => { path = "p${i}", workload = "w${i}" } }
      })
    }
  }

  assert {
    condition     = alltrue([for w in values(output.workloads) : w.node_port >= 30000 && w.node_port <= 32767])
    error_message = "A derived NodePort must be in 30000-32767: ${jsonencode({ for k, w in output.workloads : k => w.node_port })}"
  }
  assert {
    condition     = alltrue([for b in values(output.backends) : b.priority >= 1 && b.priority <= 50000])
    error_message = "A derived priority must be in 1-50000: ${jsonencode({ for k, b in output.backends : k => b.priority })}"
  }
}

run "adding_a_workload_does_not_move_the_others" {
  command = plan
  variables {
    app_sources = {
      "a.yaml" = jsonencode({
        workloads = { web = {}, extra = {}, more = {} }
        backends = {
          "eks-page" = { path = "html1", workload = "web" }
          x          = { path = "x", workload = "extra" }
          y          = { path = "y", workload = "more" }
        }
      })
    }
  }

  assert {
    condition     = output.workloads["web"].node_port == 31685 && output.backends["eks-page"].priority == 9973
    error_message = "Adding entries moved the numbers of an existing one"
  }
}
