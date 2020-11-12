terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "3.47.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "1.13.3"
    }
  }

  backend "gcs" {
    bucket = "k8s-tf-workshop"
    prefix = "terraform/demo"
  }
}

provider "google" {
  version = "3.47.0"
  region  = "us-central1"
}

variable "project" {}
variable "region" { default = "us-central1" }
variable "cluster_name" {}
variable "network" { default = "default" }
variable "subnetwork" { default = "" }
variable "ip_range_pods" { default = "" }
variable "ip_range_services" { default = "" }

module "gke" {
  source                   = "terraform-google-modules/kubernetes-engine/google"
  version                  = "12.0.0"
  project_id               = var.project
  name                     = var.cluster_name
  region                   = var.region
  zones                    = ["us-central1-a"]
  network                  = var.network
  subnetwork               = var.subnetwork
  ip_range_pods            = var.ip_range_pods
  ip_range_services        = var.ip_range_services
  kubernetes_version       = "1.17.13-gke.1400"
  create_service_account   = false
  remove_default_node_pool = true

  node_pools = [{
    name               = "microservices"
    machine_type       = "n1-standard-1"
    min_count          = 1
    max_count          = 5
    initial_node_count = 2
  }]

  node_pools_oauth_scopes = {
    all = []
    microservices = [
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring"
    ]
  }
}

data "google_client_config" "current" {}

provider "kubernetes" {
  load_config_file = false

  host                   = "https://${module.gke.endpoint}"
  cluster_ca_certificate = base64decode(module.gke.ca_certificate)
  token                  = data.google_client_config.current.access_token
}

resource "kubernetes_deployment" "example" {
  metadata {
    name = "terraform-example"
    labels = {
      test = "MyExampleApp"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        test = "MyExampleApp"
      }
    }

    template {
      metadata {
        labels = {
          test = "MyExampleApp"
        }
      }

      spec {
        container {
          image = "nginx:1.7.8"
          name  = "example"

          resources {
            limits {
              cpu    = "0.5"
              memory = "512Mi"
            }
            requests {
              cpu    = "250m"
              memory = "50Mi"
            }
          }

          liveness_probe {
            http_get {
              path = "/nginx_status"
              port = 80

              http_header {
                name  = "X-Custom-Header"
                value = "Awesome"
              }
            }

            initial_delay_seconds = 3
            period_seconds        = 3
          }
        }
      }
    }
  }
}
