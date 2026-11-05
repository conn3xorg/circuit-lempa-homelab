variable "hosts" {
  type        = any
  description = "The homelab server, as a map of one name to an address, or to a host object with an address and optional host_key, user, port, private_key_file, jump_hosts or os. Every category you turn on runs here, apart from the Wazuh server."

  validation {
    condition     = length(var.hosts) == 1
    error_message = "Give exactly one host. The stack runs on one server, with Traefik in front; to spread services over more machines, call the member circuits directly."
  }
}

variable "ssh_user" {
  type        = string
  default     = "root"
  description = "User to log in as."
}

variable "ssh_port" {
  type        = number
  default     = 22
  description = "SSH port."
}

variable "ssh_private_key_file" {
  type        = string
  default     = null
  description = "Path to a private key. When null, Conn3x uses the SSH agent."
}

variable "ssh_known_hosts_file" {
  type        = string
  default     = null
  description = "known_hosts file to check host keys against. When null, ~/.ssh/known_hosts."
}

variable "ssh_become" {
  type        = bool
  default     = false
  description = "Run commands as root through sudo."
}

# The categories, in the order the video takes them. The first three are on
# by default; the rest wait to be asked for.

variable "network" {
  type        = bool
  default     = true
  description = "Traefik in front of every web app, on ports 80 and 443, and BIND serving a zone with a name for each one."
}

variable "dashboard" {
  type        = bool
  default     = true
  description = "Homepage, with a tile for each app the stack runs."
}

variable "monitoring" {
  type        = bool
  default     = true
  description = "Uptime Kuma, Prometheus and Grafana, with Prometheus already a Grafana datasource."
}

variable "smart_home" {
  type        = bool
  default     = false
  description = "Home Assistant, on the host's network so it can find devices."
}

variable "ai" {
  type        = bool
  default     = false
  description = "Ollama, and Open WebUI to chat with its models."
}

variable "automation" {
  type        = bool
  default     = false
  description = "Kestra and Semaphore UI, and Renovate when renovate is set."
}

variable "code" {
  type        = bool
  default     = false
  description = "GitLab CE, and a GitLab Runner when gitlab_runner is true. GitLab wants a host with 8 GB of memory to itself."
}

variable "databases" {
  type        = bool
  default     = false
  description = "MariaDB, PostgreSQL and InfluxDB 3 Core, each on loopback."
}

variable "security" {
  type        = bool
  default     = false
  description = "authentik, with a PostgreSQL of its own, and Suricata. Wazuh too, when wazuh_server is set."
}

variable "containers_ui" {
  type        = bool
  default     = false
  description = "Portainer CE and Dockge, both managing Podman."
}

variable "domain" {
  type        = string
  default     = "home.arpa"
  description = "Zone the app names live in, such as \"lab.example.com\". Each app gets a name under it, such as grafana.home.arpa. home.arpa is set aside for home networks (RFC 8375), so it can't clash with a real domain."

  validation {
    condition     = can(regex("^([a-z0-9]([a-z0-9-]*[a-z0-9])?\\.)*[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.domain))
    error_message = "domain must be a lowercase DNS name without a trailing dot, such as \"home.arpa\" or \"lab.example.com\"."
  }
}

variable "address" {
  type        = string
  default     = null
  description = "IPv4 address the app names point at and BIND answers on, besides 127.0.0.1: the server's address on your network. When null, the address in hosts, which then has to be an IPv4 address."

  validation {
    condition     = var.address == null || can(cidrhost("${coalesce(var.address, "-")}/32", 0))
    error_message = "address must be an IPv4 address, such as \"192.168.1.20\"."
  }

  validation {
    condition     = !var.network || can(cidrhost("${coalesce(var.address, try(values(var.hosts)[0].address, values(var.hosts)[0]))}/32", 0))
    error_message = "The app names need an IPv4 address to point at. The host's address isn't one, so set address to the server's address on your network."
  }
}

variable "admin_email" {
  type        = string
  default     = null
  description = "Email for the admin accounts the apps create, such as \"you@example.com\". Needed by ai, automation and security."

  validation {
    condition     = var.admin_email == null || can(regex("^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]+$", coalesce(var.admin_email, "-")))
    error_message = "admin_email must be an email address, such as \"you@example.com\"."
  }

  validation {
    condition     = var.admin_email != null || !(var.ai || var.automation || var.security)
    error_message = "ai, automation and security create admin accounts: set admin_email."
  }
}

variable "admin_password" {
  type        = string
  default     = null
  ephemeral   = true
  sensitive   = true
  description = "Password for every admin account the stack sets up: Grafana's admin, and the admins of Open WebUI, Kestra, Semaphore, Portainer, GitLab, authentik and Wazuh when those run. Ephemeral: it reaches the hosts in root-only files and never the plan or state. Use passwords to give an app its own."

  validation {
    condition     = var.admin_password != null || !(var.monitoring || var.ai || var.automation || var.code || var.security || var.containers_ui)
    error_message = "Set admin_password, such as with TF_VAR_admin_password. The categories you turned on create admin accounts."
  }

  # The rules of the strictest app in the stack, so one password suits them
  # all: Wazuh's character set, Portainer's length, Kestra's mix, GitLab's
  # ban on its own name.
  validation {
    condition = var.admin_password == null || (
      can(regex("^[A-Za-z0-9.*+?-]{12,64}$", coalesce(var.admin_password, "-"))) &&
      can(regex("[A-Z]", coalesce(var.admin_password, "-"))) &&
      can(regex("[a-z]", coalesce(var.admin_password, "-"))) &&
      can(regex("[0-9]", coalesce(var.admin_password, "-"))) &&
      can(regex("[.*+?-]", coalesce(var.admin_password, "-"))) &&
      !strcontains(lower(coalesce(var.admin_password, "-")), "root") &&
      !strcontains(lower(coalesce(var.admin_password, "-")), "gitlab")
    )
    error_message = "admin_password must be 12 to 64 characters of letters, digits and . * + ? -, with an uppercase letter, a lowercase letter, a digit and one of those symbols, and without \"root\" or \"gitlab\" in it."
  }
}

variable "passwords" {
  type        = map(string)
  default     = {}
  ephemeral   = true
  sensitive   = true
  nullable    = false
  description = "Passwords that replace admin_password for one app, by name: grafana, openwebui, kestra, semaphore, portainer, gitlab, authentik, wazuh_admin or wazuh_api. Each one has to pass that app's own rules. Ephemeral, like admin_password."

  validation {
    condition     = length(setsubtract(keys(var.passwords), ["grafana", "openwebui", "kestra", "semaphore", "portainer", "gitlab", "authentik", "wazuh_admin", "wazuh_api"])) == 0
    error_message = "passwords takes the keys grafana, openwebui, kestra, semaphore, portainer, gitlab, authentik, wazuh_admin and wazuh_api."
  }
}

variable "ollama_models" {
  type        = list(string)
  default     = []
  description = "Models Ollama pulls with the ai category, such as [\"llama3.2:3b\"]."
}

variable "renovate" {
  type = object({
    platform     = string
    repositories = list(string)
    endpoint     = optional(string)
  })
  default     = null
  description = "Where Renovate runs with the automation category, such as { platform = \"gitlab\", endpoint = \"https://gitlab.example.com/api/v4\", repositories = [\"lab/infra\"] }. When null, no Renovate."
}

variable "renovate_token" {
  type        = string
  default     = null
  ephemeral   = true
  sensitive   = true
  description = "Token Renovate signs in to the platform with. Needed with renovate. Ephemeral: it reaches the host in a root-only file and never the plan or state."

  validation {
    condition     = !var.automation || var.renovate == null || var.renovate_token != null
    error_message = "renovate needs renovate_token."
  }
}

variable "gitlab_runner" {
  type        = bool
  default     = false
  description = "Run a GitLab Runner with the code category, registered with gitlab_runner_token. Create the runner in GitLab first, so this goes on with the second apply."
}

variable "gitlab_runner_token" {
  type        = string
  default     = null
  ephemeral   = true
  sensitive   = true
  description = "The glrt- token GitLab shows when you create a runner. Needed with gitlab_runner. Ephemeral, like admin_password."

  validation {
    condition     = !(var.code && var.gitlab_runner) || var.gitlab_runner_token != null
    error_message = "gitlab_runner needs gitlab_runner_token."
  }
}

variable "db_users" {
  type        = list(string)
  default     = []
  description = "Apps that get their own database, such as [\"nextcloud\"]. With the databases category, each name becomes a user and a database owned by it, in MariaDB and in PostgreSQL. Each needs a password in db_passwords."
}

variable "db_passwords" {
  type        = map(string)
  default     = {}
  ephemeral   = true
  sensitive   = true
  nullable    = false
  description = "Password for each of db_users, by name. Ephemeral, like admin_password."
}

variable "influxdb_token" {
  type        = string
  default     = null
  ephemeral   = true
  sensitive   = true
  description = "Admin token InfluxDB starts with: apiv3_ followed by at least 32 letters, digits, _ or -, such as apiv3_ and the output of openssl rand -hex 24. Needed with databases. Ephemeral, like admin_password."

  validation {
    condition     = !var.databases || can(regex("^apiv3_[A-Za-z0-9_-]{32,}$", coalesce(var.influxdb_token, "-")))
    error_message = "databases needs influxdb_token: apiv3_ followed by at least 32 letters, digits, _ or -."
  }
}

variable "wazuh_server" {
  type        = any
  default     = null
  description = "A host of its own for the Wazuh manager, indexer and dashboard, in the same form as hosts. With the security category, the homelab server joins it as an agent. Wazuh asks for 4 vCPUs and 8 GiB. When null, no Wazuh."

  validation {
    condition     = var.wazuh_server == null || try(length(var.wazuh_server) == 1, false)
    error_message = "wazuh_server is a map of one name to a host, such as { siem = \"192.168.1.40\" }."
  }
}
