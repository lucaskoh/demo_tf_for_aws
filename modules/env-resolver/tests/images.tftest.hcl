# Which image is pulled: as written, or through a proxy registry (for example a Harbor proxy cache).

variables {
  name               = "demo"
  vpc_b_subnet_cidr  = "10.1.1.0/24"
  ec2_template_names = ["nginx-demo"]
  app_sources = {
    "a.yaml" = jsonencode({
      workloads = {
        demo     = {}
        official = { image = "nginx:1.27-alpine" }
        hub      = { image = "someone/app:1", container_port = 8080 }
        explicit = { image = "docker.io/nginx", container_port = 8080 }
        ghcr     = { image = "ghcr.io/example-org/api:2.0", container_port = 8080 }
        digest   = { image = "ghcr.io/example-org/job@sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef", container_port = 8080 }
        local    = { image = "localhost:5000/app:1", container_port = 8080 }
      }
      backends = { a = { path = "a", workload = "demo" } }
    })
  }
}

run "without_proxies_images_are_pulled_as_written" {
  command = plan
  assert {
    condition = (
      output.workloads["demo"].pull_image == "nginx:1.27-alpine" &&
      output.workloads["official"].pull_image == "nginx:1.27-alpine" &&
      output.workloads["hub"].pull_image == "someone/app:1" &&
      output.workloads["ghcr"].pull_image == "ghcr.io/example-org/api:2.0" &&
      output.workloads["local"].pull_image == "localhost:5000/app:1"
    )
    error_message = jsonencode({ for k, w in output.workloads : k => w.pull_image })
  }
  assert {
    condition     = output.workloads["demo"].image == null && output.workloads["official"].image == "nginx:1.27-alpine"
    error_message = "image keeps what was written (null = the built-in demo page)"
  }
  assert {
    condition     = length(output.problems) == 0
    error_message = jsonencode(output.problems)
  }
}

run "with_proxies_every_image_goes_through_its_proxy" {
  command = plan
  variables {
    image_proxies = {
      "docker.io"      = "harbor.example.com/dockerhub"
      "ghcr.io"        = "harbor.example.com/ghcr"
      "localhost:5000" = "harbor.example.com/local"
    }
  }
  assert {
    condition     = output.workloads["official"].pull_image == "harbor.example.com/dockerhub/library/nginx:1.27-alpine"
    error_message = "An official Docker Hub image lives under library/: ${output.workloads["official"].pull_image}"
  }
  assert {
    condition     = output.workloads["hub"].pull_image == "harbor.example.com/dockerhub/someone/app:1"
    error_message = output.workloads["hub"].pull_image
  }
  assert {
    condition     = output.workloads["explicit"].pull_image == "harbor.example.com/dockerhub/library/nginx"
    error_message = "docker.io/nginx is the official image too: ${output.workloads["explicit"].pull_image}"
  }
  assert {
    condition     = output.workloads["ghcr"].pull_image == "harbor.example.com/ghcr/example-org/api:2.0"
    error_message = output.workloads["ghcr"].pull_image
  }
  assert {
    condition     = output.workloads["digest"].pull_image == "harbor.example.com/ghcr/example-org/job@sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
    error_message = "The digest must be kept: ${output.workloads["digest"].pull_image}"
  }
  assert {
    condition     = output.workloads["local"].pull_image == "harbor.example.com/local/app:1"
    error_message = "The port of a registry is part of the registry: ${output.workloads["local"].pull_image}"
  }
  assert {
    condition     = output.workloads["demo"].pull_image == "harbor.example.com/dockerhub/library/nginx:1.27-alpine" && output.workloads["demo"].image == null
    error_message = "The built-in demo page is pulled through the proxy too: ${output.workloads["demo"].pull_image}"
  }
  assert {
    condition     = length(output.problems) == 0
    error_message = jsonencode(output.problems)
  }
}

run "a_registry_without_a_proxy_is_rejected" {
  command = plan
  variables {
    image_proxies = {
      "docker.io" = "harbor.example.com/dockerhub"
    }
  }
  assert {
    condition     = length(output.problems) == 1 && strcontains(output.problems[0], "ghcr (ghcr.io/example-org/api:2.0 is on ghcr.io)")
    error_message = jsonencode(output.problems)
  }
  assert {
    condition     = strcontains(output.problems[0], "digest (ghcr.io/example-org/job@sha256") && strcontains(output.problems[0], "local (localhost:5000/app:1 is on localhost:5000)")
    error_message = jsonencode(output.problems)
  }
  assert {
    condition     = !strcontains(output.problems[0], "official (") && !strcontains(output.problems[0], "hub (")
    error_message = "Docker Hub images are covered: ${jsonencode(output.problems)}"
  }
  assert {
    condition     = strcontains(output.problems[0], "(docker.io), and these have none")
    error_message = "The message must list the registries that have a proxy: ${jsonencode(output.problems)}"
  }
}

run "the_demo_page_needs_a_docker_hub_proxy" {
  command = plan
  variables {
    image_proxies = {
      "ghcr.io" = "harbor.example.com/ghcr"
    }
    app_sources = {
      "a.yaml" = jsonencode({
        workloads = { demo = {} }
        backends  = { a = { path = "a", workload = "demo" } }
      })
    }
  }
  assert {
    condition     = length(output.problems) == 1 && strcontains(output.problems[0], "demo (nginx:1.27-alpine is on docker.io)")
    error_message = jsonencode(output.problems)
  }
}

run "the_allowlist_checks_the_image_as_written" {
  command = plan
  variables {
    allowed_images = ["nginx", "docker.io/nginx", "someone/app", "ghcr.io/example-org/", "localhost:5000/app"]
    image_proxies = {
      "docker.io"      = "harbor.example.com/dockerhub"
      "ghcr.io"        = "harbor.example.com/ghcr"
      "localhost:5000" = "harbor.example.com/local"
    }
  }
  assert {
    condition     = length(output.problems) == 0
    error_message = "Teams and the allowlist talk about the original names, not the proxy path: ${jsonencode(output.problems)}"
  }
}

run "the_allowlist_does_not_accept_the_proxy_path" {
  command = plan
  variables {
    allowed_images = ["nginx"]
    image_proxies = {
      "harbor.example.com" = "harbor.example.com/direct"
    }
    app_sources = {
      "a.yaml" = jsonencode({
        workloads = { x = { image = "harbor.example.com/dockerhub/library/nginx:1", container_port = 8080 } }
        backends  = { a = { path = "a", workload = "x" } }
      })
    }
  }
  assert {
    condition     = strcontains(join(" ", output.problems), "Not allowed: x (harbor.example.com/dockerhub/library/nginx:1)")
    error_message = jsonencode(output.problems)
  }
}
