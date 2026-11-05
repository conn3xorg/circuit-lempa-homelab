# CI copies this to ../../upgrade_override.tf to apply the stack as it was
# one release back: the members' previous tags, and older Traefik, Homepage
# and Uptime Kuma releases through the members' own inputs. Removing it and
# applying again is the upgrade.
module "podman" {
  source = "github.com/conn3xorg/circuit-podman?ref=v0.1.0"
}

module "traefik" {
  source          = "github.com/conn3xorg/circuit-traefik?ref=v0.1.0"
  traefik_version = "3.7.15"
  checksums = {
    amd64 = "5b9f51199fcb7a3b5f7ae0f9dae8dcf01efadafd92c5fca96ea2822eca81f8e6"
    arm64 = "1866d8e831b95d14b599bb59eb20d2033b979c0cb1e347b48a0866a9b810454e"
  }
}

module "bind" {
  source = "github.com/conn3xorg/circuit-bind?ref=v0.1.2"
}

module "homepage" {
  homepage_version = "v2.6.0"
  image_digest     = "sha256:3e38fe788223cb46a3ce1f046ef11667b40f7707fdca0dcbfa3f86c5c42bf1e8"
}

module "uptimekuma" {
  uptimekuma_version = "2.5.8"
  image_digest       = "sha256:20abea8c48a163cf0a7a5d5936ab418e4b742d908704e1f58f6c06e56a9c6b67"
}

module "prometheus" {
  source = "github.com/conn3xorg/circuit-prometheus?ref=v0.1.0"
}

module "grafana" {
  source = "github.com/conn3xorg/circuit-grafana?ref=v0.1.2"
}
