locals {
  host    = values(var.hosts)[0]
  address = coalesce(var.address, try(local.host.address, local.host))

  # Every app listens on loopback, on a port of its own. The defaults of
  # several members collide: Homepage, Grafana and Semaphore all want 3000,
  # Open WebUI, Kestra and GitLab's Puma 8080, and on Rocky Linux cloud
  # images cockpit.socket holds Prometheus's 9090.
  port = {
    homepage      = 3000
    uptimekuma    = 3001
    grafana       = 3002
    semaphore     = 3003
    dockge        = 5001
    openwebui     = 8081
    kestra        = 8085
    homeassistant = 8123
    gitlab        = 8929
    authentik     = 9000
    portainer     = 9443
    # authentik's HTTPS port moves off 9443, which is Portainer's.
    authentik_https = 9444
    prometheus      = 9091
  }

  # The web apps, in the order of the video's chapters. Each one that's on
  # gets a name under the domain, a Traefik route to its loopback port and a
  # tile on Homepage. Portainer only speaks HTTPS, so it's routed separately.
  apps = [
    { key = "homeassistant", on = var.smart_home, title = "Home Assistant", group = "Smart home", icon = "home-assistant.png", about = "Home automation" },
    { key = "uptimekuma", on = var.monitoring, title = "Uptime Kuma", group = "Monitoring", icon = "uptime-kuma.png", about = "Is it up?" },
    { key = "grafana", on = var.monitoring, title = "Grafana", group = "Monitoring", icon = "grafana.png", about = "Dashboards over Prometheus" },
    { key = "openwebui", on = var.ai, title = "Open WebUI", group = "AI", icon = "open-webui.png", about = "Chat with your Ollama models" },
    { key = "kestra", on = var.automation, title = "Kestra", group = "Automation", icon = "kestra.png", about = "Workflows" },
    { key = "semaphore", on = var.automation, title = "Semaphore UI", group = "Automation", icon = "semaphore.png", about = "Ansible, OpenTofu and Terraform runs" },
    { key = "gitlab", on = var.code, title = "GitLab", group = "Code", icon = "gitlab.png", about = "Git, issues and CI" },
    { key = "authentik", on = var.security, title = "authentik", group = "Security and identity", icon = "authentik.png", about = "Single sign-on" },
    { key = "portainer", on = var.containers_ui, title = "Portainer", group = "Containers", icon = "portainer.png", about = "Containers on this host" },
    { key = "dockge", on = var.containers_ui, title = "Dockge", group = "Containers", icon = "dockge.png", about = "Compose stacks" },
  ]
  on = { for a in local.apps : a.key => a if a.on }

  name = { for k, a in local.on : k => "${k}.${var.domain}" }
  # Homepage gets the short name people will type.
  names = merge(local.name, var.dashboard ? { homepage = "home.${var.domain}" } : {})

  url = { for k in keys(local.names) : k => var.network ? "https://${local.names[k]}" : "http://127.0.0.1:${local.port[k]}" }

  sites = { for k, n in local.names : k => {
    host     = n
    backends = ["http://127.0.0.1:${local.port[k]}"]
  } if k != "portainer" }

  # Traefik checks a backend's certificate, and Portainer's is self-signed.
  # This route skips the check for that one loopback hop only, the way
  # circuit-portainer's README does it with Caddy.
  portainer_route = yamlencode({
    http = {
      routers = { lempa-portainer = {
        rule        = "Host(`portainer.${var.domain}`)"
        entryPoints = ["websecure"]
        service     = "lempa-portainer"
      } }
      services = { lempa-portainer = { loadBalancer = {
        servers          = [{ url = "https://127.0.0.1:${local.port.portainer}" }]
        serversTransport = "lempa-portainer"
      } } }
      serversTransports = { lempa-portainer = { insecureSkipVerify = true } }
    }
  })

  zone = {
    (var.domain) = {
      type = "primary"
      records = concat(
        [
          { name = "@", type = "NS", value = "ns" },
          { name = "ns", type = "A", value = local.address },
        ],
        [for n in values(local.names) : { name = trimsuffix(n, ".${var.domain}"), type = "A", value = local.address }],
      )
    }
  }

  groups = distinct([for a in local.apps : a.group if a.on])
  homepage_services = [for g in local.groups : {
    (g) = [for a in local.apps : {
      (a.title) = merge(
        { href = local.url[a.key], description = a.about, icon = a.icon },
        # Homepage runs on the host's network, so it checks the loopback
        # port itself. Portainer's self-signed certificate would fail it.
        a.key == "portainer" ? {} : { siteMonitor = "http://127.0.0.1:${local.port[a.key]}" },
      )
    } if a.on && a.group == g]
  }]

  pw = { for k in ["grafana", "openwebui", "kestra", "semaphore", "portainer", "gitlab", "authentik", "wazuh_admin", "wazuh_api"] : k => lookup(var.passwords, k, var.admin_password) }

  # Secrets only the machines use, made from admin_password so there's one
  # thing to keep. Changing admin_password changes them too.
  authentik_db_password = sha256("${coalesce(var.admin_password, "-")}/authentik-postgres")
  wazuh_enrollment      = substr(sha256("${coalesce(var.admin_password, "-")}/wazuh-enrollment"), 0, 32)

  pg_users = concat(var.databases ? var.db_users : [], var.security ? ["authentik"] : [])
}

# Container orchestration. Most of the apps below run under Podman as
# systemd services, and each member installs it for itself; this makes it
# part of the stack even with every app off.
module "podman" {
  source = "github.com/conn3xorg/circuit-podman?ref=v0.1.1"

  hosts                = var.hosts
  ssh_user             = var.ssh_user
  ssh_port             = var.ssh_port
  ssh_private_key_file = var.ssh_private_key_file
  ssh_known_hosts_file = var.ssh_known_hosts_file
  ssh_become           = var.ssh_become
}

# Network management.
module "traefik" {
  source = "github.com/conn3xorg/circuit-traefik?ref=v0.1.1"
  count  = var.network ? 1 : 0

  hosts                = var.hosts
  ssh_user             = var.ssh_user
  ssh_port             = var.ssh_port
  ssh_private_key_file = var.ssh_private_key_file
  ssh_known_hosts_file = var.ssh_known_hosts_file
  ssh_become           = var.ssh_become

  sites = local.sites
}

module "bind" {
  source = "github.com/conn3xorg/circuit-bind?ref=v0.2.0"
  count  = var.network ? 1 : 0

  hosts                = var.hosts
  ssh_user             = var.ssh_user
  ssh_port             = var.ssh_port
  ssh_private_key_file = var.ssh_private_key_file
  ssh_known_hosts_file = var.ssh_known_hosts_file
  ssh_become           = var.ssh_become

  zones     = local.zone
  listen_on = distinct(["127.0.0.1", local.address])
}

circuit "lempa" {
  hosts = var.hosts

  ssh {
    user             = var.ssh_user
    port             = var.ssh_port
    private_key_file = var.ssh_private_key_file
    known_hosts_file = var.ssh_known_hosts_file
    become           = var.ssh_become
  }

  # Traefik watches its dynamic directory, so this route comes and goes
  # without a restart.
  step "portainer_route" {
    for_each = toset(var.network && var.containers_ui ? ["portainer"] : [])
    file {
      path      = "/etc/traefik/dynamic/lempa-portainer.yml"
      content   = "# Written by Conn3x. Changes here are overwritten on the next apply.\n${local.portainer_route}"
      on_remove = "delete"
    }
  }
}

# App and server management.
module "homepage" {
  source = "github.com/conn3xorg/circuit-homepage?ref=v0.1.0"
  count  = var.dashboard ? 1 : 0

  hosts                = var.hosts
  ssh_user             = var.ssh_user
  ssh_port             = var.ssh_port
  ssh_private_key_file = var.ssh_private_key_file
  ssh_known_hosts_file = var.ssh_known_hosts_file
  ssh_become           = var.ssh_become

  port          = local.port.homepage
  allowed_hosts = var.network ? [local.names.homepage] : []
  settings      = { title = "Homelab" }
  services      = local.homepage_services
}

# Monitoring and reporting.
module "uptimekuma" {
  source = "github.com/conn3xorg/circuit-uptimekuma?ref=v0.1.0"
  count  = var.monitoring ? 1 : 0

  hosts                = var.hosts
  ssh_user             = var.ssh_user
  ssh_port             = var.ssh_port
  ssh_private_key_file = var.ssh_private_key_file
  ssh_known_hosts_file = var.ssh_known_hosts_file
  ssh_become           = var.ssh_become

  port = local.port.uptimekuma
}

module "prometheus" {
  source = "github.com/conn3xorg/circuit-prometheus?ref=v0.1.1"
  count  = var.monitoring ? 1 : 0

  hosts                = var.hosts
  ssh_user             = var.ssh_user
  ssh_port             = var.ssh_port
  ssh_private_key_file = var.ssh_private_key_file
  ssh_known_hosts_file = var.ssh_known_hosts_file
  ssh_become           = var.ssh_become

  listen_address = "127.0.0.1:${local.port.prometheus}"
}

module "grafana" {
  source = "github.com/conn3xorg/circuit-grafana?ref=v0.2.0"
  count  = var.monitoring ? 1 : 0

  hosts                = var.hosts
  ssh_user             = var.ssh_user
  ssh_port             = var.ssh_port
  ssh_private_key_file = var.ssh_private_key_file
  ssh_known_hosts_file = var.ssh_known_hosts_file
  ssh_become           = var.ssh_become

  admin_password = local.pw.grafana
  http_port      = local.port.grafana
  domain         = var.network ? local.names.grafana : null
  root_url       = var.network ? "${local.url.grafana}/" : null
  datasources = [{
    name       = "Prometheus"
    type       = "prometheus"
    uid        = "prometheus"
    url        = "http://127.0.0.1:${local.port.prometheus}"
    is_default = true
  }]
}

# IoT and smart home.
module "homeassistant" {
  source = "github.com/conn3xorg/circuit-homeassistant?ref=v0.1.0"
  count  = var.smart_home ? 1 : 0

  hosts                = var.hosts
  ssh_user             = var.ssh_user
  ssh_port             = var.ssh_port
  ssh_private_key_file = var.ssh_private_key_file
  ssh_known_hosts_file = var.ssh_known_hosts_file
  ssh_become           = var.ssh_become

  trusted_proxies = var.network ? ["127.0.0.1"] : []
}

# AI.
module "ollama" {
  source = "github.com/conn3xorg/circuit-ollama?ref=v0.1.2"
  count  = var.ai ? 1 : 0

  hosts                = var.hosts
  ssh_user             = var.ssh_user
  ssh_port             = var.ssh_port
  ssh_private_key_file = var.ssh_private_key_file
  ssh_known_hosts_file = var.ssh_known_hosts_file
  ssh_become           = var.ssh_become

  models = var.ollama_models
}

module "openwebui" {
  source = "github.com/conn3xorg/circuit-openwebui?ref=v0.1.1"
  count  = var.ai ? 1 : 0

  hosts                = var.hosts
  ssh_user             = var.ssh_user
  ssh_port             = var.ssh_port
  ssh_private_key_file = var.ssh_private_key_file
  ssh_known_hosts_file = var.ssh_known_hosts_file
  ssh_become           = var.ssh_become

  port           = local.port.openwebui
  admin_email    = var.admin_email
  admin_password = local.pw.openwebui
}

# Automation.
module "kestra" {
  source = "github.com/conn3xorg/circuit-kestra?ref=v0.1.0"
  count  = var.automation ? 1 : 0

  hosts                = var.hosts
  ssh_user             = var.ssh_user
  ssh_port             = var.ssh_port
  ssh_private_key_file = var.ssh_private_key_file
  ssh_known_hosts_file = var.ssh_known_hosts_file
  ssh_become           = var.ssh_become

  port           = local.port.kestra
  public_url     = var.network ? local.url.kestra : null
  admin          = { email = var.admin_email }
  admin_password = local.pw.kestra
}

module "semaphore" {
  source = "github.com/conn3xorg/circuit-semaphore?ref=v0.1.0"
  count  = var.automation ? 1 : 0

  hosts                = var.hosts
  ssh_user             = var.ssh_user
  ssh_port             = var.ssh_port
  ssh_private_key_file = var.ssh_private_key_file
  ssh_known_hosts_file = var.ssh_known_hosts_file
  ssh_become           = var.ssh_become

  port           = local.port.semaphore
  public_url     = var.network ? local.url.semaphore : null
  admin          = { email = var.admin_email }
  admin_password = local.pw.semaphore
}

module "renovate" {
  source = "github.com/conn3xorg/circuit-renovate?ref=v0.1.0"
  count  = var.automation && var.renovate != null ? 1 : 0

  hosts                = var.hosts
  ssh_user             = var.ssh_user
  ssh_port             = var.ssh_port
  ssh_private_key_file = var.ssh_private_key_file
  ssh_known_hosts_file = var.ssh_known_hosts_file
  ssh_become           = var.ssh_become

  platform     = var.renovate.platform
  endpoint     = var.renovate.endpoint
  repositories = var.renovate.repositories
  token        = var.renovate_token
}

# Code management. GitLab's bundled NGINX serves plain HTTP on loopback for
# Traefik, and its bundled Prometheus stays off: it would take the ports of
# the stack's own exporters and duplicate Prometheus.
module "gitlab" {
  source = "github.com/conn3xorg/circuit-gitlab?ref=v0.1.1"
  count  = var.code ? 1 : 0

  hosts                = var.hosts
  ssh_user             = var.ssh_user
  ssh_port             = var.ssh_port
  ssh_private_key_file = var.ssh_private_key_file
  ssh_known_hosts_file = var.ssh_known_hosts_file
  ssh_become           = var.ssh_become

  external_url  = local.url.gitlab
  root_password = local.pw.gitlab
  reverse_proxy = { listen_port = local.port.gitlab, trusted_proxies = ["127.0.0.1"] }
  extra_config  = <<-EOT
    nginx['listen_addresses'] = ['127.0.0.1']
    prometheus_monitoring['enable'] = false
  EOT
}

module "gitlab_runner" {
  source = "github.com/conn3xorg/circuit-gitlab-runner?ref=v0.1.1"
  count  = var.code && var.gitlab_runner ? 1 : 0

  hosts                = var.hosts
  ssh_user             = var.ssh_user
  ssh_port             = var.ssh_port
  ssh_private_key_file = var.ssh_private_key_file
  ssh_known_hosts_file = var.ssh_known_hosts_file
  ssh_become           = var.ssh_become

  gitlab_url   = local.url.gitlab
  runner_token = var.gitlab_runner_token
}

# Databases. authentik keeps its data in the same PostgreSQL.
module "mariadb" {
  source = "github.com/conn3xorg/circuit-mariadb?ref=v0.3.0"
  count  = var.databases ? 1 : 0

  hosts                = var.hosts
  ssh_user             = var.ssh_user
  ssh_port             = var.ssh_port
  ssh_private_key_file = var.ssh_private_key_file
  ssh_known_hosts_file = var.ssh_known_hosts_file
  ssh_become           = var.ssh_become

  users          = var.db_users
  user_passwords = var.db_passwords
  databases      = var.db_users
  grants         = [for u in var.db_users : { user = u, database = u }]
}

module "postgres" {
  source = "github.com/conn3xorg/circuit-postgres?ref=v0.3.0"
  count  = var.databases || var.security ? 1 : 0

  hosts                = var.hosts
  ssh_user             = var.ssh_user
  ssh_port             = var.ssh_port
  ssh_private_key_file = var.ssh_private_key_file
  ssh_known_hosts_file = var.ssh_known_hosts_file
  ssh_become           = var.ssh_become

  users          = local.pg_users
  databases      = { for u in local.pg_users : u => u }
  user_passwords = merge(var.databases ? var.db_passwords : {}, var.security ? { authentik = local.authentik_db_password } : {})
}

module "influxdb" {
  source = "github.com/conn3xorg/circuit-influxdb?ref=v0.1.0"
  count  = var.databases ? 1 : 0

  hosts                = var.hosts
  ssh_user             = var.ssh_user
  ssh_port             = var.ssh_port
  ssh_private_key_file = var.ssh_private_key_file
  ssh_known_hosts_file = var.ssh_known_hosts_file
  ssh_become           = var.ssh_become

  admin_token = var.influxdb_token
}

# Security and identity.
module "authentik" {
  source = "github.com/conn3xorg/circuit-authentik?ref=v0.1.2"
  count  = var.security ? 1 : 0

  depends_on = [module.postgres]

  hosts                = var.hosts
  ssh_user             = var.ssh_user
  ssh_port             = var.ssh_port
  ssh_private_key_file = var.ssh_private_key_file
  ssh_known_hosts_file = var.ssh_known_hosts_file
  ssh_become           = var.ssh_become

  public_url         = local.url.authentik
  port               = local.port.authentik
  https_port         = local.port.authentik_https
  postgres_password  = local.authentik_db_password
  bootstrap_email    = var.admin_email
  bootstrap_password = local.pw.authentik
}

module "suricata" {
  source = "github.com/conn3xorg/circuit-suricata?ref=v0.2.0"
  count  = var.security ? 1 : 0

  hosts                = var.hosts
  ssh_user             = var.ssh_user
  ssh_port             = var.ssh_port
  ssh_private_key_file = var.ssh_private_key_file
  ssh_known_hosts_file = var.ssh_known_hosts_file
  ssh_become           = var.ssh_become
}

# Wazuh's indexer takes 127.0.0.1:9300 on its own host, where authentik keeps
# its metrics, and wants 8 GiB besides. So the server gets a host of its own,
# and the homelab server reports to it as an agent.
module "wazuh" {
  source = "github.com/conn3xorg/circuit-wazuh?ref=v0.2.0"
  count  = var.security && var.wazuh_server != null ? 1 : 0

  server               = var.wazuh_server
  agents               = var.hosts
  ssh_user             = var.ssh_user
  ssh_port             = var.ssh_port
  ssh_private_key_file = var.ssh_private_key_file
  ssh_known_hosts_file = var.ssh_known_hosts_file
  ssh_become           = var.ssh_become

  admin_password      = local.pw.wazuh_admin
  api_password        = local.pw.wazuh_api
  enrollment_password = local.wazuh_enrollment
}

# Containers in the browser.
module "portainer" {
  source = "github.com/conn3xorg/circuit-portainer?ref=v0.1.0"
  count  = var.containers_ui ? 1 : 0

  hosts                = var.hosts
  ssh_user             = var.ssh_user
  ssh_port             = var.ssh_port
  ssh_private_key_file = var.ssh_private_key_file
  ssh_known_hosts_file = var.ssh_known_hosts_file
  ssh_become           = var.ssh_become

  admin_password = local.pw.portainer
}

module "dockge" {
  source = "github.com/conn3xorg/circuit-dockge?ref=v0.1.0"
  count  = var.containers_ui ? 1 : 0

  hosts                = var.hosts
  ssh_user             = var.ssh_user
  ssh_port             = var.ssh_port
  ssh_private_key_file = var.ssh_private_key_file
  ssh_known_hosts_file = var.ssh_known_hosts_file
  ssh_become           = var.ssh_become

  port = local.port.dockge
}
