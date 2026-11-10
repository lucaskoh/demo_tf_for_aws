# A workload that nobody routes to has no NodePort (null): a ClusterIP Service. The validation of
# node_port must accept null without comparing it (older Terraform evaluates both sides of ||).

mock_provider "kubernetes" {}

variables {
  name  = "app-test"
  image = "nginx:1.27-alpine"
}

run "no_node_port_is_a_cluster_ip" {
  command = plan
  variables {
    node_port = null
  }
  assert {
    condition     = kubernetes_service_v1.app.spec[0].type == "ClusterIP"
    error_message = "Without a NodePort the Service must be a ClusterIP: ${kubernetes_service_v1.app.spec[0].type}"
  }
}

run "a_node_port_is_a_node_port_service" {
  command = plan
  variables {
    node_port = 31000
  }
  assert {
    condition     = kubernetes_service_v1.app.spec[0].type == "NodePort"
    error_message = kubernetes_service_v1.app.spec[0].type
  }
}

run "a_node_port_out_of_range_is_rejected" {
  command = plan
  variables {
    node_port = 29999
  }
  expect_failures = [var.node_port]
}
