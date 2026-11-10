# Reading and merging the app files. These runs read real folders (tests/fixtures); the paths are
# relative to the module folder, where `terraform test` runs.

variables {
  name               = "demo"
  vpc_b_subnet_cidr  = "10.1.1.0/24"
  ec2_template_names = ["nginx-demo"]
}

run "files_in_sub_folders_are_merged" {
  command = plan
  variables {
    apps_dir = "tests/fixtures/team"
  }

  assert {
    condition     = jsonencode(sort(keys(output.workloads))) == "[\"web\"]" && jsonencode(sort(keys(output.instances))) == "[\"legacy\"]"
    error_message = "workloads: ${jsonencode(keys(output.workloads))}, instances: ${jsonencode(keys(output.instances))}"
  }
  assert {
    condition     = jsonencode(sort(keys(output.backends))) == "[\"front\",\"legacy-page\"]"
    error_message = "backends: ${jsonencode(keys(output.backends))}"
  }
  assert {
    condition     = output.backends["legacy-page"].instance == "legacy" && jsonencode(output.instances["legacy"].paths) == "[\"legacy\"]"
    error_message = "A backend may point to an instance defined in another file"
  }
  assert {
    condition     = length(output.problems) == 0
    error_message = "Unexpected problems (empty sections are fine): ${jsonencode(output.problems)}"
  }
}

run "files_that_are_not_yaml_are_reported_not_ignored_silently" {
  command = plan
  variables {
    apps_dir = "tests/fixtures/ignored"
  }

  assert {
    condition     = length(output.problems) == 1 && strcontains(output.problems[0], "team.yml") && strcontains(output.problems[0], "a.yaml.bak")
    error_message = "Expected one problem that names the files: ${jsonencode(output.problems)}"
  }
  assert {
    condition     = jsonencode(keys(output.workloads)) == "[\"web\"]"
    error_message = "Only the .yaml files are read: ${jsonencode(keys(output.workloads))}"
  }
}

run "same_content_in_one_file_or_in_several_gives_the_same_result" {
  command = plan
  variables {
    app_sources = {
      "all.yaml" = <<-EOT
        workloads:
          web: {}
        instances:
          legacy:
            template: nginx-demo
        backends:
          front:
            path: front
            workload: web
          legacy-page:
            path: legacy
            instance: legacy
      EOT
    }
  }

  assert {
    condition     = jsonencode(output.backends) == jsonencode(run.files_in_sub_folders_are_merged.backends)
    error_message = "The result must not depend on how the content is split into files"
  }
  assert {
    condition     = jsonencode(output.workloads) == jsonencode(run.files_in_sub_folders_are_merged.workloads)
    error_message = "The result must not depend on how the content is split into files"
  }
}
