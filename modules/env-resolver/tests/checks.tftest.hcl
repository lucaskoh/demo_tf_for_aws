# One run per rule in checks.tf: the environment is wrong in exactly that way and the rule must
# say so (the text it must contain is the part a person needs to fix it). The first run
# checks that a correct environment has no problems at all.

variables {
  name               = "demo"
  vpc_b_subnet_cidr  = "10.1.1.0/24"
  ec2_template_names = ["nginx-demo"]
  # A correct environment; each run replaces it
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

run "a_correct_environment_has_no_problems" {
  command = plan
  assert {
    condition     = length(output.problems) == 0
    error_message = "Unexpected problems: ${jsonencode(output.problems)}"
  }
}

run "section_left_in_values_yaml" {
  command = plan
  variables {
    platform_sections = ["common", "network", "workloads"]
  }
  assert {
    condition     = length(output.problems) == 1 && strcontains(output.problems[0], "does not declare workloads any more")
    error_message = jsonencode(output.problems)
  }
}

run "name_defined_in_two_files" {
  command = plan
  variables {
    app_sources = {
      "a.yaml" = jsonencode({ workloads = { web = {} }, backends = { home = { path = "home", workload = "web" } } })
      "b.yaml" = jsonencode({ workloads = { web = { replicas = 2 } } })
    }
  }
  assert {
    condition     = length(output.problems) == 1 && strcontains(output.problems[0], "workload 'web' is defined in apps/a.yaml and apps/b.yaml")
    error_message = jsonencode(output.problems)
  }
}

run "name_defined_in_two_folders" {
  command = plan
  variables {
    app_sources = {
      "team-a/app.yaml" = jsonencode({ instances = { box = { template = "nginx-demo" } }, backends = { one = { path = "one", instance = "box" } } })
      "team-b/app.yaml" = jsonencode({ backends = { one = { path = "two", instance = "box" } } })
    }
  }
  assert {
    condition     = length(output.problems) == 1 && strcontains(output.problems[0], "backend 'one' is defined in apps/team-a/app.yaml and apps/team-b/app.yaml")
    error_message = jsonencode(output.problems)
  }
}

run "file_that_is_not_yaml" {
  command = plan
  variables {
    app_sources = {
      "a.yaml"     = jsonencode({ workloads = { web = {} }, backends = { home = { path = "home", workload = "web" } } })
      "team.yml"   = "workloads: {}"
      "b.yaml.bak" = "workloads: {}"
    }
  }
  assert {
    condition     = length(output.problems) == 1 && strcontains(output.problems[0], "These are ignored: b.yaml.bak, team.yml")
    error_message = jsonencode(output.problems)
  }
}

run "no_backend" {
  command = plan
  variables {
    app_sources = { "a.yaml" = jsonencode({ workloads = { web = {} } }) }
  }
  assert {
    condition     = length(output.problems) == 1 && strcontains(output.problems[0], "at least one backend")
    error_message = jsonencode(output.problems)
  }
}

run "bad_names" {
  command = plan
  variables {
    app_sources = {
      "a.yaml" = jsonencode({
        workloads = { Up_Case = {} }
        backends  = { "a-very-long-backend-name-here" = { path = "x", workload = "Up_Case" } }
      })
    }
  }
  assert {
    condition     = length(output.problems) == 1 && strcontains(output.problems[0], "Rename: Up_Case, a-very-long-backend-name-here")
    error_message = jsonencode(output.problems)
  }
  assert {
    condition     = strcontains(output.problems[0], "'demo-<backend>-tg' must be at most 32 characters")
    error_message = "The message must show the platform name: ${jsonencode(output.problems)}"
  }
}

run "more_workload_backends_than_the_auto_scaling_group_allows" {
  command = plan
  variables {
    app_sources = {
      "a.yaml" = jsonencode({
        workloads = { web = {} }
        backends  = { for i in range(11) : "b${i}" => { path = "p${i}", workload = "web" } }
      })
    }
  }
  assert {
    condition     = length(output.problems) == 1 && strcontains(output.problems[0], "11 backends point to workloads") && strcontains(output.problems[0], "attached to 10 target groups")
    error_message = jsonencode(output.problems)
  }
}

run "ten_workload_backends_are_fine" {
  command = plan
  variables {
    app_sources = {
      "a.yaml" = jsonencode({
        workloads = { web = {} }
        backends  = { for i in range(10) : "b${i}" => { path = "p${i}", workload = "web" } }
      })
    }
  }
  assert {
    condition     = length(output.problems) == 0
    error_message = jsonencode(output.problems)
  }
}

run "the_limit_can_be_raised" {
  command = plan
  variables {
    max_asg_target_groups = 20
    app_sources = {
      "a.yaml" = jsonencode({
        workloads = { web = {} }
        backends  = { for i in range(11) : "b${i}" => { path = "p${i}", workload = "web" } }
      })
    }
  }
  assert {
    condition     = length(output.problems) == 0
    error_message = jsonencode(output.problems)
  }
}

run "unknown_template" {
  command = plan
  variables {
    app_sources = {
      "a.yaml" = jsonencode({
        instances = { a = { template = "windows" } }
        backends  = { one = { path = "one", instance = "a" } }
      })
    }
  }
  assert {
    condition     = length(output.problems) == 1 && strcontains(output.problems[0], "(nginx-demo). Check: a.")
    error_message = "The message must list the available templates: ${jsonencode(output.problems)}"
  }
}

run "missing_template" {
  command = plan
  variables {
    app_sources = {
      "a.yaml" = jsonencode({
        instances = { b = {} }
        backends  = { one = { path = "one", instance = "b" } }
      })
    }
  }
  assert {
    condition     = length(output.problems) == 1 && strcontains(output.problems[0], "Check: b.")
    error_message = jsonencode(output.problems)
  }
}

run "backend_to_something_that_does_not_exist" {
  command = plan
  variables {
    app_sources = {
      "a.yaml" = jsonencode({ backends = { home = { path = "home", workload = "missing" } } })
    }
  }
  assert {
    condition     = length(output.problems) == 1 && strcontains(output.problems[0], "exactly one target") && strcontains(output.problems[0], "Check: home.")
    error_message = jsonencode(output.problems)
  }
}

run "backend_with_two_targets" {
  command = plan
  variables {
    app_sources = {
      "a.yaml" = jsonencode({
        workloads = { web = {} }
        instances = { box = { template = "nginx-demo" } }
        backends  = { both = { path = "both", workload = "web", instance = "box" } }
      })
    }
  }
  assert {
    condition     = length(output.problems) == 1 && strcontains(output.problems[0], "Check: both.")
    error_message = jsonencode(output.problems)
  }
}

run "backend_without_target" {
  command = plan
  variables {
    app_sources = {
      "a.yaml" = jsonencode({ backends = { none = { path = "none" } } })
    }
  }
  assert {
    condition     = length(output.problems) == 1 && strcontains(output.problems[0], "Check: none.")
    error_message = jsonencode(output.problems)
  }
}

run "path_with_a_slash" {
  command = plan
  variables {
    app_sources = {
      "a.yaml" = jsonencode({
        workloads = { web = {} }
        backends  = { home = { path = "/bad/path", workload = "web" } }
      })
    }
  }
  assert {
    condition     = length(output.problems) == 1 && strcontains(output.problems[0], "one URL segment") && strcontains(output.problems[0], "Check: home.")
    error_message = jsonencode(output.problems)
  }
}

run "same_path_twice" {
  command = plan
  variables {
    app_sources = {
      "a.yaml" = jsonencode({
        workloads = { web = {}, api = {} }
        backends = {
          a = { path = "dup", workload = "web" }
          b = { path = "dup", workload = "api" }
        }
      })
    }
  }
  assert {
    condition     = length(output.problems) == 1 && strcontains(output.problems[0], "Used more than once: dup")
    error_message = jsonencode(output.problems)
  }
}

run "priority_collision_suggests_a_free_value" {
  command = plan
  variables {
    app_sources = {
      "a.yaml" = jsonencode({
        workloads = { web = {}, api = {} }
        backends = {
          a = { path = "a", workload = "web", priority = 100 }
          b = { path = "b", workload = "api", priority = 100 }
        }
      })
    }
  }
  assert {
    condition     = length(output.problems) == 1 && strcontains(output.problems[0], "Two backends got the same priority")
    error_message = jsonencode(output.problems)
  }
  # The first one by name keeps its number; the other one gets a suggestion
  assert {
    condition     = strcontains(output.problems[0], "backend 'b': priority: 1795") && !strcontains(output.problems[0], "backend 'a': priority: ")
    error_message = jsonencode(output.problems)
  }
}

run "priority_suggestion_is_a_value_that_works" {
  command = plan
  variables {
    app_sources = {
      "a.yaml" = jsonencode({
        workloads = { web = {}, api = {} }
        backends = {
          a = { path = "a", workload = "web", priority = 100 }
          b = { path = "b", workload = "api", priority = 1795 }
        }
      })
    }
  }
  # 1795 is the suggestion for backend 'b' when 'a' and 'b' both have 100 (see the run above)
  assert {
    condition     = length(output.problems) == 0
    error_message = "The suggested value was not accepted: ${jsonencode(output.problems)}"
  }
}

run "priority_out_of_range" {
  command = plan
  variables {
    app_sources = {
      "a.yaml" = jsonencode({
        workloads = { web = {} }
        backends  = { a = { path = "a", workload = "web", priority = 50001 } }
      })
    }
  }
  assert {
    condition     = length(output.problems) == 1 && strcontains(output.problems[0], "Out of range: a.")
    error_message = jsonencode(output.problems)
  }
}

run "node_port_collision_suggests_a_free_value" {
  command = plan
  variables {
    app_sources = {
      "a.yaml" = jsonencode({
        workloads = { alpha = { node_port = 31000 }, beta = { node_port = 31000 } }
        backends = {
          a = { path = "a", workload = "alpha" }
          b = { path = "b", workload = "beta" }
        }
      })
    }
  }
  assert {
    condition     = length(output.problems) == 1 && strcontains(output.problems[0], "Two workloads got the same NodePort")
    error_message = jsonencode(output.problems)
  }
  assert {
    condition     = strcontains(output.problems[0], "workload 'beta': node_port: 30683") && !strcontains(output.problems[0], "workload 'alpha': node_port: ")
    error_message = jsonencode(output.problems)
  }
}

run "node_port_suggestion_is_a_value_that_works" {
  # 30683 is the suggestion for workload 'beta' when 'alpha' and 'beta' both have 31000 (see the run above)
  command = plan
  variables {
    app_sources = {
      "a.yaml" = jsonencode({
        workloads = { alpha = { node_port = 31000 }, beta = { node_port = 30683 } }
        backends = {
          a = { path = "a", workload = "alpha" }
          b = { path = "b", workload = "beta" }
        }
      })
    }
  }
  assert {
    condition     = length(output.problems) == 0
    error_message = jsonencode(output.problems)
  }
}

run "node_port_out_of_range" {
  command = plan
  variables {
    app_sources = {
      "a.yaml" = jsonencode({
        workloads = { web = { node_port = 29999 } }
        backends  = { a = { path = "a", workload = "web" } }
      })
    }
  }
  assert {
    condition     = length(output.problems) == 1 && strcontains(output.problems[0], "Check: web.")
    error_message = jsonencode(output.problems)
  }
}

run "unrouted_workload_node_port_is_not_checked" {
  command = plan
  variables {
    app_sources = {
      "a.yaml" = jsonencode({
        workloads = { web = {}, worker = { node_port = 1 } }
        backends  = { a = { path = "a", workload = "web" } }
      })
    }
  }
  assert {
    condition     = length(output.problems) == 0
    error_message = "A workload nobody routes to has no NodePort: ${jsonencode(output.problems)}"
  }
}

run "demo_page_needs_port_80" {
  command = plan
  variables {
    app_sources = {
      "a.yaml" = jsonencode({
        workloads = { web = { container_port = 8080 } }
        backends  = { a = { path = "a", workload = "web" } }
      })
    }
  }
  assert {
    condition     = length(output.problems) == 1 && strcontains(output.problems[0], "built-in Nginx demo page, which listens on port 80") && strcontains(output.problems[0], ": web.")
    error_message = jsonencode(output.problems)
  }
}

run "custom_image_may_use_another_port" {
  command = plan
  variables {
    app_sources = {
      "a.yaml" = jsonencode({
        workloads = { api = { image = "ghcr.io/example/api:1.0", container_port = 8080 } }
        backends  = { a = { path = "a", workload = "api" } }
      })
    }
  }
  assert {
    condition     = length(output.problems) == 0
    error_message = jsonencode(output.problems)
  }
}

run "container_port_out_of_range" {
  command = plan
  variables {
    app_sources = {
      "a.yaml" = jsonencode({
        workloads = { api = { image = "nginx:1.27", container_port = 70000 } }
        backends  = { a = { path = "a", workload = "api" } }
      })
    }
  }
  assert {
    condition     = length(output.problems) == 1 && strcontains(output.problems[0], "container_port must be between 1 and 65535") && strcontains(output.problems[0], "Check: api.")
    error_message = jsonencode(output.problems)
  }
}

run "instance_ip_duplicate_outside_and_malformed" {
  command = plan
  variables {
    app_sources = {
      "a.yaml" = jsonencode({
        instances = {
          one   = { template = "nginx-demo", private_ip = "10.1.1.50" }
          two   = { template = "nginx-demo", private_ip = "10.1.1.50" }
          three = { template = "nginx-demo", private_ip = "10.9.9.9" }
          four  = { template = "nginx-demo", private_ip = "not-an-ip" }
        }
        backends = { a = { path = "a", instance = "one" } }
      })
    }
  }
  assert {
    condition     = length(output.problems) == 1 && strcontains(output.problems[0], "inside the VPC-B subnet 10.1.1.0/24")
    error_message = jsonencode(output.problems)
  }
  assert {
    condition = (
      strcontains(output.problems[0], "four") && strcontains(output.problems[0], "three") &&
      strcontains(output.problems[0], "one") && strcontains(output.problems[0], "two")
    )
    error_message = "All four must be named: ${jsonencode(output.problems)}"
  }
}

run "instance_ip_inside_the_subnet_is_fine" {
  command = plan
  variables {
    app_sources = {
      "a.yaml" = jsonencode({
        instances = { one = { template = "nginx-demo", private_ip = "10.1.1.50" } }
        backends  = { a = { path = "a", instance = "one" } }
      })
    }
  }
  assert {
    condition     = length(output.problems) == 0
    error_message = jsonencode(output.problems)
  }
}

run "markup_in_page_texts" {
  command = plan
  variables {
    app_sources = {
      "a.yaml" = jsonencode({
        workloads = { web = { page_heading = "<b>x</b>" } }
        instances = { box = { template = "nginx-demo", page_title = "two\nlines" } }
        backends = {
          a = { path = "a", workload = "web" }
          b = { path = "b", instance = "box" }
        }
      })
    }
  }
  assert {
    condition     = length(output.problems) == 1 && strcontains(output.problems[0], "Check: web, box.")
    error_message = jsonencode(output.problems)
  }
}

run "bad_image_and_health_check_path" {
  command = plan
  variables {
    app_sources = {
      "a.yaml" = jsonencode({
        workloads = {
          web = { image = "bad image!" }
          api = { image = "nginx:1.27", health_check_path = "healthz" }
        }
        backends = {
          a = { path = "a", workload = "web" }
          b = { path = "b", workload = "api" }
        }
      })
    }
  }
  assert {
    condition     = length(output.problems) == 1 && strcontains(output.problems[0], "Check: web, api")
    error_message = jsonencode(output.problems)
  }
}

run "all_problems_are_reported_at_once" {
  command = plan
  variables {
    app_sources = {
      "a.yaml" = jsonencode({
        workloads = { web = { image = "bad image!" } }
        backends = {
          a = { path = "dup", workload = "web" }
          b = { path = "dup", workload = "web" }
        }
      })
    }
  }
  assert {
    condition     = length(output.problems) == 2
    error_message = "Expected the duplicate path and the bad image: ${jsonencode(output.problems)}"
  }
}

# ---- image allowlist (common.allowed_images) ----

run "no_allowlist_means_any_image" {
  command = plan
  variables {
    app_sources = {
      "a.yaml" = jsonencode({
        workloads = { api = { image = "docker.io/anyone/anything:latest", container_port = 8080 } }
        backends  = { a = { path = "a", workload = "api" } }
      })
    }
  }
  assert {
    condition     = length(output.problems) == 0
    error_message = jsonencode(output.problems)
  }
}

run "exact_repository_allows_any_tag_digest_or_none" {
  command = plan
  variables {
    allowed_images = ["nginx"]
    app_sources = {
      "a.yaml" = jsonencode({
        workloads = {
          one   = { image = "nginx:1.27-alpine" }
          two   = { image = "nginx" }
          three = { image = "nginx@sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef" }
          four  = { image = "nginx:1.27@sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef" }
        }
        backends = {
          a = { path = "a", workload = "one" }
          b = { path = "b", workload = "two" }
          c = { path = "c", workload = "three" }
          d = { path = "d", workload = "four" }
        }
      })
    }
  }
  assert {
    condition     = length(output.problems) == 0
    error_message = jsonencode(output.problems)
  }
}

run "a_similar_name_is_not_the_same_repository" {
  command = plan
  variables {
    allowed_images = ["nginx"]
    app_sources = {
      "a.yaml" = jsonencode({
        workloads = {
          evil  = { image = "nginxevil/x:1" }
          other = { image = "nginx/unit:1" }
        }
        backends = {
          a = { path = "a", workload = "evil" }
          b = { path = "b", workload = "other" }
        }
      })
    }
  }
  assert {
    condition     = length(output.problems) == 1 && strcontains(output.problems[0], "evil (nginxevil/x:1), other (nginx/unit:1)")
    error_message = jsonencode(output.problems)
  }
  assert {
    condition     = strcontains(output.problems[0], "common.allowed_images of values.yaml (nginx)") && strcontains(output.problems[0], "ask the platform team")
    error_message = "The message must list the allowed entries and say what to do: ${jsonencode(output.problems)}"
  }
}

run "a_path_prefix_allows_everything_beneath_it" {
  command = plan
  variables {
    allowed_images = ["ghcr.io/example-org/", "nginx"]
    app_sources = {
      "a.yaml" = jsonencode({
        workloads = {
          one = { image = "ghcr.io/example-org/api:2.0", container_port = 8080 }
          two = { image = "ghcr.io/example-org/team/worker@sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef", container_port = 8080 }
        }
        backends = {
          a = { path = "a", workload = "one" }
          b = { path = "b", workload = "two" }
        }
      })
    }
  }
  assert {
    condition     = length(output.problems) == 0
    error_message = jsonencode(output.problems)
  }
}

run "a_path_prefix_does_not_match_a_longer_organisation_name" {
  command = plan
  variables {
    allowed_images = ["ghcr.io/example-org/"]
    app_sources = {
      "a.yaml" = jsonencode({
        workloads = {
          ok  = { image = "ghcr.io/example-org/api:1", container_port = 8080 }
          bad = { image = "ghcr.io/example-org-evil/api:1", container_port = 8080 }
        }
        backends = {
          a = { path = "a", workload = "ok" }
          b = { path = "b", workload = "bad" }
        }
      })
    }
  }
  assert {
    condition     = length(output.problems) == 1 && strcontains(output.problems[0], "Not allowed: bad (ghcr.io/example-org-evil/api:1).")
    error_message = jsonencode(output.problems)
  }
}

run "the_port_of_a_registry_is_not_a_tag" {
  command = plan
  variables {
    allowed_images = ["localhost:5000/app", "registry.example.com:8443/"]
    app_sources = {
      "a.yaml" = jsonencode({
        workloads = {
          one   = { image = "localhost:5000/app:1", container_port = 8080 }
          two   = { image = "localhost:5000/app", container_port = 8080 }
          three = { image = "registry.example.com:8443/team/x:1", container_port = 8080 }
          four  = { image = "localhost:5000/other:1", container_port = 8080 }
        }
        backends = {
          a = { path = "a", workload = "one" }
          b = { path = "b", workload = "two" }
          c = { path = "c", workload = "three" }
          d = { path = "d", workload = "four" }
        }
      })
    }
  }
  assert {
    condition     = length(output.problems) == 1 && strcontains(output.problems[0], "Not allowed: four (localhost:5000/other:1).")
    error_message = jsonencode(output.problems)
  }
}

run "the_built_in_demo_page_needs_no_allowlist_entry" {
  command = plan
  variables {
    allowed_images = ["ghcr.io/example-org/"]
  }
  assert {
    condition     = length(output.problems) == 0
    error_message = "A workload without image is the platform's own demo page: ${jsonencode(output.problems)}"
  }
}

run "an_unrouted_workload_is_checked_too" {
  command = plan
  variables {
    allowed_images = ["nginx"]
    app_sources = {
      "a.yaml" = jsonencode({
        workloads = { web = {}, worker = { image = "docker.io/anyone/job:1" } }
        backends  = { a = { path = "a", workload = "web" } }
      })
    }
  }
  assert {
    condition     = length(output.problems) == 1 && strcontains(output.problems[0], "worker (docker.io/anyone/job:1)")
    error_message = jsonencode(output.problems)
  }
}

run "a_prefix_must_match_the_start_of_the_image" {
  command = plan
  variables {
    allowed_images = ["ghcr.io/example-org/"]
    app_sources = {
      "a.yaml" = jsonencode({
        workloads = { sneaky = { image = "evil.example/ghcr.io/example-org/api:1", container_port = 8080 } }
        backends  = { a = { path = "a", workload = "sneaky" } }
      })
    }
  }
  assert {
    condition     = length(output.problems) == 1 && strcontains(output.problems[0], "sneaky")
    error_message = jsonencode(output.problems)
  }
}
