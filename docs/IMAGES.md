# Container Image Versions

All active image tags are in `inventory/group_vars/all/images.yml`, grouped by
service. Edit a quoted tag there; registries and image names remain in the
roles. Save the file in Git so changes are reviewable and reproducible.

For example, to change Sonarr, edit `media_versions.sonarr`, then preview and
apply the media roles while the Pi has internet:

```bash
ansible-playbook playbooks/site.yml --tags media --check --diff
ansible-playbook playbooks/site.yml --tags media
```

Use `--tags monitoring`, `--tags identity`, `--tags dockge`, or `--tags proxy`
for those groups. Applying a tag can restart the affected services. Check the
role's documentation and verify the service afterward. For a wider change,
combine tags with commas. `scripts/media-check-updates.sh` and
`scripts/monitoring-check.sh --updates` offer advisory update reports; they
need internet and do not change versions. A project release does not guarantee
that the corresponding ARM64 container tag exists.

Normal media and monitoring deployments use cached images when the requested
tag is already present, avoiding unnecessary registry requests on weak Wi-Fi.
A tag change can pull and start a new image. Review release and migration notes
first, particularly for Authelia configuration, Jellyfin databases and PostgreSQL
major versions; downgrading may require restoring a backup. Re-pulling an
unchanged tag is separate: media and monitoring support `--tags media_update
-e media_update=true` and `--tags monitoring_update -e monitoring_update=true`
respectively.

Traefik and AudioBookRequest use specific release tags matching the images
that were running when they were pinned. Even a version tag may be republished;
digest references provide stronger guarantees, but the tag fields in this file
do not currently accept digests.
