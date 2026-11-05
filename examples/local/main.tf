variable "port" {
  type    = number
  default = 2222
}

# Example value only. CI checks it never reaches the state.
variable "admin_password" {
  type      = string
  default   = "Example-lab-pass-1"
  ephemeral = true
  sensitive = true
}

# The default stack: Podman, Traefik and BIND, Homepage, Uptime Kuma,
# Prometheus and Grafana. The container's SSH port is forwarded to
# 127.0.0.1, so that's the address the app names point at too.
module "homelab" {
  source = "../.."

  hosts                = { box = "127.0.0.1" }
  ssh_port             = var.port
  ssh_private_key_file = "./id_ed25519"
  ssh_known_hosts_file = "./known_hosts"

  admin_password = var.admin_password
}

output "urls" {
  value = module.homelab.urls
}
