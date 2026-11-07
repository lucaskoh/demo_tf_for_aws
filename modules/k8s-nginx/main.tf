locals {
  index_html = "<!DOCTYPE html><html><head><meta charset=\"utf-8\"><title>EKS</title></head><body><h1>Hello from EKS (VPC-A)</h1><img src=\"${var.image_url}\" alt=\"EKS logo\" width=\"200\"></body></html>"
  labels     = { app = var.name }
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
    replicas = 1

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
            container_port = 80
          }

          volume_mount {
            name       = "html"
            mount_path = "/usr/share/nginx/html/html1/index.html"
            sub_path   = "index.html"
            read_only  = true
          }

          readiness_probe {
            http_get {
              path = "/html1/index.html"
              port = 80
            }

            initial_delay_seconds = 2
            period_seconds        = 5
          }

          resources {
            requests = {
              cpu    = "50m"
              memory = "32Mi"
            }

            limits = {
              memory = "128Mi"
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
      port        = 80
      target_port = 80
      node_port   = var.node_port
    }
  }
}
