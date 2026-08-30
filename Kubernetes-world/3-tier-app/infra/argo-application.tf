# argo application for the 3-tier-app

# uncomment the code when you have setup the argo cd in the cluster

provider "argocd" {
  server_addr = "argocd.mansipandey.in"
  username    = "admin"
  password    = "IWHdyr20UOX5rSNH"
}

resource "argocd_application" "devopsdozo" {
  metadata {
    name      = "devopsdozo"
    namespace = "argocd"
  }

  wait = true

  spec {
    project = "default"

    destination {
      server    = "https://kubernetes.default.svc"
    }

    source {
      repo_url        = "https://github.com/akhileshmishrabiz/April26-bootcamp"
      path            = "Kubernetes-world/3-tier-app/k8s"
      target_revision = "main"
    }

    sync_policy {
      automated {
        prune     = true
        self_heal = true
      }
    }
  }
}