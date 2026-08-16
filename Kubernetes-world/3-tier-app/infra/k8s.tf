# namespcae
resource "kubernetes_namespace" "devopsdozo" {
  metadata {

    labels = {
      name = "devopsdozo"
    }

    name = "devopsdozo"
  }
}
# backend secrets
resource "kubernetes_secret" "backend_secret" {
  metadata {
    name = "backend-secret"
    namespace = kubernetes_namespace.devopsdozo.metadata[0].name
  }

  data = {
    DB_LINK = aws_secretsmanager_secret_version.dbs_secret_val.secret_string
    SECRET_KEY = random_password.backend_secret_key.result
    DB_USERNAME = aws_db_instance.postgres.username
    DB_PASSWORD = random_password.db_password.result
  }

  type = "Opaque"
}

# backend config
resource "kubernetes_config_map" "backend_config" {
  metadata {
    name = "backend-config"
    namespace = kubernetes_namespace.devopsdozo.metadata[0].name
  }

  data = {
    APP_VERSION = "1.0.0"
    APP_NAME = "backend"
    DB_HOST = aws_db_instance.postgres.address
    DB_PORT = aws_db_instance.postgres.port
    DB_NAME = aws_db_instance.postgres.db_name
    ALLOWED_ORIGINS = "frontend-service.devopsdozo.svc.cluster.local:3000"
  }
}

# frontend config

resource "kubernetes_config_map" "frontend_config" {
  metadata {
    name = "frontend-config"
    namespace = kubernetes_namespace.devopsdozo.metadata[0].name
  }

  data = {
    APP_VERSION = "1.0.0"
    APP_NAME = "frontend"
    BACKEND_URL = "backend-service.devopsdozo.svc.cluster.local:8000"
  }
}

# services backend and frontend

resource "kubernetes_service" "backend_service" {
  metadata {
    name      = "backend-service"
    namespace = kubernetes_namespace.devopsdozo.metadata[0].name
  }

  spec {
    # The selector maps incoming traffic to pods matching this label
    selector = {
      app = "backend"
    }

    # Define how network traffic is routed
    port {
      port        = 8000          # Port exposed by the service
      target_port = 8000          # Port the container listens on inside the pod
      protocol    = "TCP"       # Network protocol (TCP or UDP)
    }

    # Service types: ClusterIP, NodePort, LoadBalancer, or ExternalName
    type = "ClusterIP"
  }
}


resource "kubernetes_service" "frontend_service" {
  metadata {
    name      = "frontend-service"
    namespace = kubernetes_namespace.devopsdozo.metadata[0].name
  }

  spec {
    # The selector maps incoming traffic to pods matching this label
    selector = {
      app = "frontend"
    }

    # Define how network traffic is routed
    port {
      port        = 3000          # Port exposed by the service
      target_port = 3000          # Port the container listens on inside the pod
      protocol    = "TCP"       # Network protocol (TCP or UDP)
    }

    # Service types: ClusterIP, NodePort, LoadBalancer, or ExternalName
    type = "ClusterIP"
  }
}