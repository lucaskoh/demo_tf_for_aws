locals {
  labels = { app = var.name }
}

# Only when a static file is mounted (the demo page)
resource "kubernetes_config_map_v1" "static" {
  count = var.static_file != null ? 1 : 0

  metadata {
    name      = var.name
    namespace = var.namespace
    labels    = local.labels
  }

  data = {
    "file" = var.static_file.content
  }
}

resource "kubernetes_deployment_v1" "app" {
  metadata {
    name      = var.name
    namespace = var.namespace
    labels    = local.labels
  }

  spec {
    replicas = var.replicas

    selector {
      match_labels = local.labels
    }

    template {
      metadata {
        labels = local.labels

        # Restart the pods when the mounted file changes
        annotations = var.static_file != null ? {
          "checksum/static-file" = sha256(var.static_file.content)
        } : {}
      }

      spec {
        container {
          name  = "app"
          image = var.image

          port {
            container_port = var.container_port
          }

          dynamic "volume_mount" {
            for_each = var.static_file != null ? [var.static_file] : []

            content {
              name       = "static-file"
              mount_path = volume_mount.value.mount_path
              sub_path   = "file"
              read_only  = true
            }
          }

          readiness_probe {
            http_get {
              path = var.health_check_path
              port = var.container_port
            }

            initial_delay_seconds = 2
            period_seconds        = 5
          }

          resources {
            requests = {
              cpu    = var.resources.cpu_request
              memory = var.resources.memory_request
            }

            limits = {
              memory = var.resources.memory_limit
            }
          }
        }

        dynamic "volume" {
          for_each = var.static_file != null ? [1] : []

          content {
            name = "static-file"

            config_map {
              name = kubernetes_config_map_v1.static[0].metadata[0].name
            }
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "app" {
  metadata {
    name      = var.name
    namespace = var.namespace
    labels    = local.labels
  }

  spec {
    type     = "NodePort"
    selector = local.labels

    port {
      port        = var.service_port
      target_port = var.container_port
      node_port   = var.node_port
    }
  }
}
