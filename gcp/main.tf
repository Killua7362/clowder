locals {
  project_id = "clowder-403113"
  credentials = "../credentials.json"
  region = "asia-south1"
  zone = "asia-south1-a"
  image = "debian-cloud/debian-11"
  machine_type = "n2-highcpu-8"
}


provider "google" {
  project =local.project_id
  credentials = file(local.credentials)
  region =local.region
  zone = local.zone
}

resource "google_compute_disk" "killua-disk" {
  name = "killua-disk"
  zone = local.zone
  image = local.image
}

resource "google_compute_instance" "killua" {
  name = "clowder"
  machine_type =local.machine_type
  zone = local.zone
  allow_stopping_for_update = true
  tags = [ "ssh" ]
  boot_disk {
      source = google_compute_disk.killua-disk.self_link
  }

  network_interface {
    network = google_compute_network.clowder-network.self_link
    subnetwork = google_compute_subnetwork.clowder-subnet.self_link
    access_config {
     
    }
  }
  provisioner "remote-exec" {
     connection{
          type = "ssh"
          user = "killua"
          host = google_compute_instance.killua.network_interface.0.access_config.0.nat_ip
          private_key = file("~/.ssh/ansible_ed25519")
      }
      inline = [ 
        "sudo apt-get update",
        "sudo apt-get install -y python"
        ]
  }

  provisioner "local-exec" {
    command = "ansible-playbook  -i ${self.network_interface.0.access_config.0.nat_ip}, --private-key ~/.ssh/ansible_ed25519 install.yaml -e ansible_python_interpreter=/usr/bin/python3"
  }

}

resource "google_compute_network" "clowder-network" {
  name = "clowder-network"
  auto_create_subnetworks = false
  delete_default_routes_on_create = true
}

resource "google_compute_subnetwork" "clowder-subnet" {
  name = "clowder-subnet"
  ip_cidr_range =  "10.20.0.0/16"
  region = local.region
  network = google_compute_network.clowder-network.id 
}

resource "google_compute_router" "clowder-router" {
  name = "clowder-router"
  network = google_compute_network.clowder-network.self_link
}

resource "google_compute_router_nat" "internet-access" {
  name = "internet-access"
  router = google_compute_router.clowder-router.name
  region = google_compute_router.clowder-router.region
  nat_ip_allocate_option = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}

resource "google_compute_route" "private-network-route" {
  name = "private-network-route"
  dest_range = "0.0.0.0/0"
  network = google_compute_network.clowder-network.self_link
  next_hop_gateway = "default-internet-gateway"
  priority = 100
  
}

resource "google_compute_firewall" "ssh" {
  name = "allow-ssh"
  network = google_compute_network.clowder-network.self_link
  allow {
    protocol = "tcp"
    ports = ["80","22","8080"]
  }
  source_ranges = ["0.0.0.0/0"]
  target_tags = ["ssh"]
}

output "Web-server-URL" {
 value = join("",["http://",google_compute_instance.killua.network_interface.0.access_config.0.nat_ip,":5000"])
}

resource "google_artifact_registry_repository" "clowder-images" {
  location      = "asia-south1"
  repository_id = "clowder-images"
  description   = "Contains all the applications"
  format        = "DOCKER"
}