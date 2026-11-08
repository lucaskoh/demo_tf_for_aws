locals {
  index_html = "<!DOCTYPE html><html><head><meta charset=\"utf-8\"><title>${var.page_title}</title></head><body><h1>${var.page_heading}</h1><img src=\"${var.image_url}\" alt=\"${var.image_alt}\" width=\"200\"></body></html>"
  labels     = { app = var.name }

  # The Nginx image listens on port 80 (fixed by the image)
  container_port = 80
}

resource "kubernetes_config_map_v1" "html" {
  metadata {
    name      = var.name
    namespace = var.namespace
    labels    = local.labels
  }

  data = {
    "index.html" = local.index_html
  }
}

resource "kubernetes_deployment_v1" "nginx" {
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

        annotations = {
          # Restart the pod when the page content changes
          "checksum/html" = sha256(local.index_html)
        }
      }

      spec {
        container {
          name  = "nginx"
          image = var.image

          port {
            container_port = local.container_port
          }

          volume_mount {
            name       = "html"
            mount_path = "/usr/share/nginx/html/${var.path_prefix}/index.html"
            sub_path   = "index.html"
            read_only  = true
          }

          readiness_probe {
            http_get {
              path = "/${var.path_prefix}/index.html"
              port = local.container_port
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

        volume {
          name = "html"

          config_map {
            name = kubernetes_config_map_v1.html.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "nginx" {
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
      target_port = local.container_port
      node_port   = var.node_port
    }
  }
}
