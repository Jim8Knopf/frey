# Projekt-Verbesserungen & TODOs

Dies ist eine Liste von potenziellen Verbesserungen und nächsten Schritten, um das Projekt noch robuster und professioneller zu machen.

## 🚀 Nächste Schritte

- [ ] **Sicherheit erhöhen: Passwörter mit Ansible Vault verschlüsseln**
  - **Warum?** Um sensible Daten wie Passwörter sicher zu speichern und das Projekt gefahrlos in einem Git-Repository verwalten zu können.
  - **Wie?**
    1. Eine verschlüsselte Datei erstellen: `ansible-vault create group_vars/secrets.yml`
    2. Passwörter aus `group_vars/all.yml` dorthin verschieben.
    3. Playbook mit `--ask-vault-pass` ausführen.

- [ ] **Traefik-Integration vervollständigen**
  - **Warum?** Um alle Dienste über einfach zu merkende Domains (z.B. `grafana.frey`) statt über IP-Adressen und Ports erreichbar zu machen.
  - **Wie?** Die Traefik-Labels (wie bei Jellyfin und Dockge bereits geschehen) zu den Docker-Compose-Dateien der restlichen Dienste hinzufügen (z.B. Grafana, Portainer, Sonarr, Radarr etc.).

- [ ] **Backup-Skript optimieren**
  - **Warum?** Um die Backup-Größe und -Dauer zu reduzieren, indem unnötige Cache-Verzeichnisse ausgeschlossen werden.
  - **Wie?** Das Backup-Skript (`roles/backup/templates/backup.sh.j2`) um `--exclude`-Parameter für `tar` erweitern, z.B. für `appdata/jellyfin/cache`.

- [ ] **HTTPS mit Let's Encrypt aktivieren**
  - **Warum?** Um die gesamte Kommunikation mit den Diensten zu verschlüsseln. Dies ist ein fortgeschrittener Schritt, der eine öffentlich erreichbare Domain und offene Ports (80/443) erfordert.
  - **Wie?** Die Traefik-Konfiguration um einen "Certificate Resolver" für Let's Encrypt erweitern.

- [ ] **System-Benachrichtigungen einrichten**
  - **Warum?** Um proaktiv über den Systemzustand, abgeschlossene Backups oder Probleme informiert zu werden.
  - **Wie?** Einen Dienst wie `ntfy` oder `gotify` hinzufügen und die Skripte (z.B. `backup.sh`, `health_check.sh`) so anpassen, dass sie bei Abschluss oder Fehlern eine Benachrichtigung senden.