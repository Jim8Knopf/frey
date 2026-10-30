# Wi-Fi portal

The Wi-Fi tile opens an admin-only page for connecting to saved NetworkManager
uplink profiles. It only lists infrastructure profiles explicitly bound to the
configured uplink interface. It cannot alter the FreyHub access point or add
new networks. Networks declared in the vault survive a rebuild; open networks
remembered by the automatic selector can also be selected.

Traefik requires Authelia's `frey_admins` group and supplies a private token
to the host-side service. The service rejects direct requests without that
token and requires same-origin POST requests. The token and generated proxy
configuration are root-readable only. The portal listens only on the Docker
proxy network's host-side gateway.
