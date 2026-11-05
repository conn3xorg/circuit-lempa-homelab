output "urls" {
  description = "Where to open each web app, by name, such as { grafana = \"https://grafana.home.arpa\" }. With network off, the loopback address on the host, for an SSH tunnel."
  value       = local.url
}

output "dns_records" {
  description = "The names BIND serves, each pointing at address. Point your network's DNS at the server for the domain, or add these to it."
  value       = { for k, n in local.names : n => local.address }
}
