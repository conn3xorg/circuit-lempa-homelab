# Local example

Applies the default stack (Podman, Traefik, BIND, Homepage, Uptime Kuma, Prometheus and Grafana) to a throwaway Rocky Linux 10 container with systemd. You need Conn3x and Podman.

The apps run under Podman inside that container, so the host container is privileged, which is simplest with rootful Podman. On a Mac, use the Podman machine's root connection. On Linux, use `sudo podman`:

```sh
export CONTAINER_CONNECTION=podman-machine-default-root   # macOS
export PODMAN="sudo podman"                               # Linux
./up.sh
conn3x init
conn3x apply
conn3x plan
```

The first apply takes a minute or two, with the parts installing side by side. The second plan says `No changes.` `main.tf` sets an example `admin_password`; Grafana's user is `admin`.

The container's SSH port is forwarded to `127.0.0.1`, so that's the address the app names point at. To open the apps in your browser, forward port 443 over SSH and add the names to your hosts file:

```sh
ssh -p 2222 -i id_ed25519 -o UserKnownHostsFile=known_hosts -L 443:127.0.0.1:443 root@127.0.0.1
# /etc/hosts:  127.0.0.1  home.home.arpa uptimekuma.home.arpa grafana.home.arpa
```

Then open `https://home.home.arpa` and accept Traefik's self-signed certificate.

[`check.sh`](check.sh) is what CI runs instead of a browser. It asks BIND for each name, fetches each app through Traefik by name, finds the tiles on Homepage, reaches Uptime Kuma's socket.io, and has Grafana query Prometheus:

```sh
LAB_PASSWORD=Example-lab-pass-1 podman exec -i -e LAB_PASSWORD circuit-lempa-homelab bash -s < check.sh   # on Linux: sudo --preserve-env=LAB_PASSWORD podman
```

CI also applies the stack one release back first, from [`previous-release.hcl`](previous-release.hcl), then upgrades it, and plans every other category against the same host with [`every-category.hcl`](every-category.hcl).

`up.sh` listens on `127.0.0.1:2222`. Set `PORT` to use another port, and pass the same port to Conn3x with `-var port=PORT`. Set `CONTAINER_NAME` to name the container something other than `circuit-lempa-homelab`, and pass it to `down.sh` too. Set `CONTAINERFILE` to test another distro, such as one of the images in Conn3x's `test/images`, which CI uses.

`./down.sh` removes the container, its volumes, the key and the state.
