# CI copies this to every_category_override.tf to plan the categories it
# doesn't apply. The tokens are placeholders: nothing is applied with them.
module "homelab" {
  smart_home    = true
  ai            = true
  automation    = true
  code          = true
  databases     = true
  security      = true
  containers_ui = true

  admin_email   = "admin@example.com"
  ollama_models = ["smollm2:135m"]

  renovate       = { platform = "gitlab", endpoint = "https://gitlab.home.arpa/api/v4", repositories = ["lab/infra"] }
  renovate_token = "placeholder-renovate-token"

  gitlab_runner       = true
  gitlab_runner_token = "glrt-placeholder"

  db_users       = ["nextcloud"]
  db_passwords   = { nextcloud = "Example-db-pass-1" }
  influxdb_token = "apiv3_placeholder0123456789abcdef0123456789"
}
