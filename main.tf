################################################################################
# Load Vendor Corp Shared Infra
################################################################################
module "shared" {
  source                   = "git::ssh://git@github.com/vendorcorp/terraform-shared-infrastructure.git?ref=v0.3.0"
  environment              = var.environment
  default_eks_cluster_name = "vendorcorp-us-east-2-63pl3dng"
}

################################################################################
# PostgreSQL Provider
################################################################################
provider "postgresql" {
  scheme          = "awspostgres"
  host            = module.shared.pgsql_cluster_endpoint_write
  port            = module.shared.pgsql_cluster_port
  database        = "postgres"
  username        = module.shared.pgsql_cluster_master_username
  password        = var.pgsql_password
  sslmode         = "require"
  connect_timeout = 15
  superuser       = false
}

################################################################################
# PostgreSQL Role and Database
################################################################################
locals {
  pgsql_database = "${var.nxrm_instance_purpose}_nxrm"
  pgsql_username = "${var.nxrm_instance_purpose}_nxrm"
}

resource "postgresql_role" "nxrm" {
  name     = local.pgsql_username
  login    = true
  password = local.pgsql_user_password
}

resource "postgresql_grant_role" "grant_root" {
  role              = module.shared.pgsql_cluster_master_username
  grant_role        = postgresql_role.nxrm.name
  with_admin_option = true
}

resource "postgresql_database" "nxrm" {
  name              = local.pgsql_database
  owner             = local.pgsql_username
  template          = "template0"
  lc_collate        = "C"
  connection_limit  = -1
  allow_connections = true
}

################################################################################
# Connect to our k8s Cluster
################################################################################
provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = module.shared.eks_cluster_arn
}

################################################################################
# k8s Namespace
################################################################################
resource "kubernetes_namespace" "nxrm" {
  metadata {
    # annotations = {
    #   name = "example-annotation"
    # }

    # labels = {
    #   mylabel = "label-value"
    # }

    name = var.target_namespace
  }
}

################################################################################
# k8s StorageClass for Local Node Storage
################################################################################
resource "kubernetes_storage_class" "local_node" {
  metadata {
    name = "local-node-storage"
    # namespace = kubernetes_namespace.nxrm.metadata["name"]
  }
  storage_provisioner = "kubernetes.io/no-provisioner"
  volume_binding_mode = "WaitForFirstConsumer"
}

################################################################################
# k8s Secrets
################################################################################
resource "kubernetes_secret" "nxrm3" {
  metadata {
    name      = "sonatype-nxrm3"
    namespace = var.target_namespace
  }

  binary_data = {
    "license.lic" = filebase64("${path.module}/sonatype-license.lic")
  }

  data = {
    "pgsql_password" = local.pgsql_user_password
  }

  type = "Opaque"
}

################################################################################
# Create PersistentVolume
################################################################################
resource "kubernetes_persistent_volume" "nxrm" {
  metadata {
    name = "nxrm-pv"
  }
  spec {
    capacity = {
      storage = "120Gi"
    }
    volume_mode                      = "Filesystem"
    access_modes                     = ["ReadWriteOnce"]
    persistent_volume_reclaim_policy = "Retain"
    storage_class_name               = "local-node-storage"
    persistent_volume_source {
      local {
        path = "/mnt"
      }
    }
    node_affinity {
      required {
        node_selector_term {
          match_expressions {
            key      = "instancegroup"
            operator = "In"
            values   = ["shared"]
          }
        }
        node_selector_term {
          match_expressions {
            key      = "topology.kubernetes.io/zone"
            operator = "In"
            values   = module.shared.availability_zones
          }
        }
      }
    }
  }
}

################################################################################
# Create PersistentVolumeClaim
################################################################################
resource "kubernetes_persistent_volume_claim" "nxrm3" {
  metadata {
    name      = "nxrm-pvc"
    namespace = var.target_namespace
  }
  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = "local-node-storage"
    resources {
      requests = {
        storage = "100Gi"
      }
    }
  }
}

################################################################################
# Create Deployment for NXRM
################################################################################
resource "kubernetes_deployment" "nxrm3" {
  metadata {
    name      = "${var.nxrm_instance_purpose}-nxrm3"
    namespace = var.target_namespace
    labels = {
      app = "nxrm3"
    }
  }
  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "nxrm3"
      }
    }

    template {
      metadata {
        labels = {
          app = "nxrm3"
        }
      }

      spec {
        node_selector = {
          instancegroup = "shared"
        }

        init_container {
          name    = "chown-nexusdata-owner-to-nexus-and-init-log-dir"
          image   = "busybox:1.33.1"
          command = ["/bin/sh"]
          args = [
            "-c",
            ">- mkdir -p /nexus-data/etc/logback && mkdir -p /nexus-data/log/tasks && mkdir -p /nexus-data/log/audit && touch -a /nexus-data/log/tasks/allTasks.log && touch -a /nexus-data/log/audit/audit.log && touch -a /nexus-data/log/request.log && chown -R '200:200' /nexus-data"
          ]
          volume_mount {
            mount_path = "/nexus-data"
            name       = "nxrm3-data"
          }
        }

        container {
          image             = "sonatype/nexus3:3.38.1"
          name              = "nxrm3-app"
          image_pull_policy = "IfNotPresent"

          env {
            name  = "DB_HOST"
            value = module.shared.pgsql_cluster_endpoint_write
          }

          env {
            name  = "DB_NAME"
            value = local.pgsql_database
          }

          env {
            name = "DB_PASSWORD"
            value_from {
              secret_key_ref {
                name = "sonatype-nxrm3"
                key  = "pgsql_password"
              }
            }
          }

          env {
            name  = "DB_PORT"
            value = module.shared.pgsql_cluster_port
          }

          env {
            name  = "DB_USER"
            value = local.pgsql_username
          }

          env {
            name  = "NEXUS_SECURITY_RANDOMPASSWORD"
            value = false
          }

          env {
            name  = "INSTALL4J_ADD_VM_PARAMS"
            value = "-Xms2703m -Xmx2703m -XX:MaxDirectMemorySize=2703m -Dnexus.licenseFile=/nxrm3-secrets/license.lic"
          }

          # -Dnexus.datastore.enabled=true 
          # -Djava.util.prefs.userRoot=$${NEXUS_DATA}/javaprefs 
          # -Dnexus.datastore.nexus.jdbcUrl=jdbc:postgresql://$${DB_HOST}:$${DB_PORT}/$${DB_NAME} 
          # -Dnexus.datastore.nexus.username=$${DB_USER} 
          # -Dnexus.datastore.nexus.password=$${DB_PASSWORD}

          port {
            container_port = 8081
          }

          security_context {
            run_as_user = 200
          }

          volume_mount {
            mount_path = "/nexus-data"
            name       = "nxrm3-data"
          }

          volume_mount {
            mount_path = "/nxrm3-secrets"
            name       = "nxrm3-secrets"
          }
        }

        volume {
          name = "nxrm3-data"
          persistent_volume_claim {
            claim_name = "nxrm-pvc"
          }
        }

        volume {
          name = "nxrm3-secrets"
          secret {
            secret_name = "sonatype-nxrm3"
          }
        }
      }
    }
  }
}

################################################################################
# Create Service for NXRM3
################################################################################
resource "kubernetes_service" "nxrm3" {
  metadata {
    name      = "nxrm3-service"
    namespace = var.target_namespace
    labels = {
      app = "nxrm3"
    }
  }
  spec {
    selector = {
      app = kubernetes_deployment.nxrm3.metadata.0.labels.app
    }

    port {
      name        = "http"
      port        = 8081
      target_port = 8081
      protocol    = "TCP"
    }

    type = "NodePort"
  }
  # wait_for_load_balancer = true
}

################################################################################
# Create Ingress for NXRM3
################################################################################
resource "kubernetes_ingress" "nxrm3" {
  metadata {
    name      = "nxrm3-ingress"
    namespace = var.target_namespace
    labels = {
      app = "nxmr3"
    }
    annotations = {
      "kubernetes.io/ingress.class"               = "alb"
      "alb.ingress.kubernetes.io/group.name"      = "vencorcorp-shared-core"
      "alb.ingress.kubernetes.io/scheme"          = "internal"
      "alb.ingress.kubernetes.io/certificate-arn" = module.shared.vendorcorp_net_cert_arn
    }
  }

  spec {
    rule {
      host = "nxrm3.corp.${module.shared.dns_zone_public_name}"
      http {
        path {
          path = "/*"
          backend {
            service_name = "nxrm3-service"
            service_port = 8081
          }
        }
      }
    }
  }

  wait_for_load_balancer = true
}

################################################################################
# Add/Update DNS for Load Balancer Ingress
################################################################################
resource "aws_route53_record" "keycloak_dns" {
  zone_id = module.shared.dns_zone_public_id
  name    = "nxrm3.corp"
  type    = "CNAME"
  ttl     = "300"
  records = [
    kubernetes_ingress.nxrm3.status.0.load_balancer.0.ingress.0.hostname
  ]
}
