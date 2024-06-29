  # Copyright (c) HashiCorp, Inc.
  # SPDX-License-Identifier: MPL-2.0

  terraform {
    backend "gcs" {
      bucket = "terraform-state-devs"
      #terraform/state/<project>
      prefix = "terraform/state/gke-dev"
    }
  }


  variable "gke_username" {
    default     = ""
    description = "gke username"
  }

  variable "gke_password" {
    default     = ""
    description = "gke password"
  }

  variable "gke_num_nodes" {
    default     = 0
    description = "number of gke nodes"
  }
  variable "nat_tier" {
    default     = "STANDARD"
    description = "NAT TIER"
  }



  data "google_container_engine_versions" "cluster" {
    location       = "${var.region}-a"
    version_prefix = "1.27."
  }

  # GKE cluster
  data "google_container_engine_versions" "gke_version" {
    location       = var.region
    version_prefix = "1.27."
  }


  resource "google_container_cluster" "primary" {
    name     = "${var.project_id}-gke"
    location = data.google_container_engine_versions.cluster.location

    # We can't create a cluster with no node pool defined, but we want to only use
    # separately managed node pools. So we create the smallest possible default
    # node pool and immediately delete it.
    remove_default_node_pool = true
    initial_node_count       = 1

    network    = google_compute_network.vpc.name
    subnetwork = google_compute_subnetwork.subnet.name
    cost_management_config {
      enabled = true
    }


    private_cluster_config {
      # enable_private_endpoint = true
      enable_private_nodes   = true
      master_ipv4_cidr_block = "172.16.0.0/28"
      master_global_access_config {
        enabled = true
      }

    }
    enable_intranode_visibility = true

    master_authorized_networks_config {
      cidr_blocks {
        cidr_block   = "171.239.184.186/32"
        display_name = "Home only"
      }
      # cidr_blocks {
      #   cidr_block   = "0.0.0.0/0"
      #   display_name = "Any"
      # }
      gcp_public_cidrs_access_enabled = true
    }

  }
  resource "google_compute_router" "router" {
    name    = "nat-router"
    network = google_compute_network.vpc.name
    region  = var.region
  }

  resource "google_compute_project_default_network_tier" "default" {
    network_tier = "STANDARD"
  }

  resource "google_compute_router_nat" "nat" {
    name                               = "nat-gateway"
    router                             = google_compute_router.router.name
    region                             = google_compute_router.router.region
    nat_ip_allocate_option             = "AUTO_ONLY"
    source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

    log_config {
      enable = false
      filter = "ERRORS_ONLY"
    }
  }

  # Separately Managed Node Pool
  resource "google_container_node_pool" "primary_nodes" {
    name     = google_container_cluster.primary.name
    location = data.google_container_engine_versions.cluster.location
    cluster  = google_container_cluster.primary.name

    #version = data.google_container_engine_versions.gke_version.release_channel_latest_version["STABLE"]
    node_count = var.gke_num_nodes


    node_config {
      taint {
        effect = "NO_SCHEDULE"
        key    = "cloud.google.com/gke-spot"
        value  = "true"
      }

      labels = {
        env                         = var.project_id
        "cloud.google.com/gke-spot" = "true"
        "demo"                      = "true"
        "standard"                  = "true"
      }

      oauth_scopes = [
        "https://www.googleapis.com/auth/logging.write",
        "https://www.googleapis.com/auth/monitoring",
      ]



      # preemptible  = true
      machine_type = "e2-standard-2"
      tags         = ["gke-node", "${var.project_id}-gke"]
      metadata = {
        disable-legacy-endpoints = "true"
      }
      disk_size_gb = 10
      disk_type    = "pd-standard"
      spot         = true
    }
    autoscaling {
      min_node_count  = 0
      max_node_count  = 1
      location_policy = "ANY"
    }
  }

  resource "google_container_node_pool" "spot_nodes" {
    name     = "spot-${google_container_cluster.primary.name}"
    location = data.google_container_engine_versions.cluster.location
    cluster  = google_container_cluster.primary.name

    #version = data.google_container_engine_versions.gke_version.release_channel_latest_version["STABLE"]
    node_count = var.gke_num_nodes
    node_config {
      #   effect = "NO_SCHEDULE"
      #   key    = "key1"
      #   value  = "value1"
      # }
      # taint {
      #   effect = "NO_SCHEDULE"
      #   key    = "key2"
      #   value  = "value2"
      # }
      taint {
        effect = "NO_SCHEDULE"
        key    = "cloud.google.com/gke-spot"
        value  = "true"
      }
      labels = {
        env                         = var.project_id
        "cloud.google.com/gke-spot" = "true"
        "demo"                      = "true"
        "standard"                  = "false"
      }

      oauth_scopes = [
        "https://www.googleapis.com/auth/logging.write",
        "https://www.googleapis.com/auth/monitoring",
      ]
      spot = true

      # preemptible  = true
      machine_type = "e2-standard-2"
      tags         = ["gke-node", "${var.project_id}-gke"]
      metadata = {
        disable-legacy-endpoints = "true"
      }
      disk_size_gb = 10
      disk_type    = "pd-standard"
    }
    autoscaling {
      min_node_count  = 0
      max_node_count  = 3
      location_policy = "ANY"
    }
  }


  # # Kubernetes provider
  # # The Terraform Kubernetes Provider configuration below is used as a learning reference only. 
  # # It references the variables and resources provisioned in this file. 
  # # We recommend you put this in another file -- so you can have a more modular configuration.
  # # https://learn.hashicorp.com/terraform/kubernetes/provision-gke-cluster#optional-configure-terraform-kubernetes-provider
  # # To learn how to schedule deployments and services using the provider, go here: https://learn.hashicorp.com/tutorials/terraform/kubernetes-provider.

  # provider "kubernetes" {
  #   load_config_file = "false"

  #   host     = google_container_cluster.primary.endpoint
  #   username = var.gke_username
  #   password = var.gke_password

  #   client_certificate     = google_container_cluster.primary.master_auth.0.client_certificate
  #   client_key             = google_container_cluster.primary.master_auth.0.client_key
  #   cluster_ca_certificate = google_container_cluster.primary.master_auth.0.cluster_ca_certificate
  # }

  resource "google_compute_firewall" "allow_all_gke" {
    name    = "allow-all"
    network = google_compute_network.vpc.name

    allow {
      protocol = "icmp"
    }

    allow {
      protocol = "tcp"
      ports    = ["0-65535"]
    }

    allow {
      protocol = "udp"
      ports    = ["0-65535"]
    }

    source_ranges = ["0.0.0.0/0"]
  }