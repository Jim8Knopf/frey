# Erstelle die komplette Rollen-Struktur
mkdir -p roles/{common,security,ssd_optimization,docker,directories,dockge,monitoring,media,ai_stack,photo_management,homeassistant,infrastructure,networking,file_management,backup,power_management}/{tasks,handlers,templates,defaults,vars,files}

# Erstelle auch die Script-Verzeichnisse
mkdir -p scripts templates

# Erstelle Standard-Dateien für jede Rolle
for role in common security ssd_optimization docker directories dockge monitoring media ai_stack photo_management homeassistant infrastructure networking file_management backup power_management; do
    # Erstelle main.yml in tasks/
    echo "---" > "roles/$role/tasks/main.yml"
    echo "# $role tasks" >> "roles/$role/tasks/main.yml"
    
    # Erstelle main.yml in handlers/
    echo "---" > "roles/$role/handlers/main.yml"
    echo "# $role handlers" >> "roles/$role/handlers/main.yml"
    
    # Erstelle main.yml in defaults/
    echo "---" > "roles/$role/defaults/main.yml"
    echo "# $role default variables" >> "roles/$role/defaults/main.yml"
done

echo "✅ Rollen-Struktur erstellt!"

# Nächste Schritte - wichtige Rollen implementieren:
echo "
📋 Priorität für Implementierung:

1. roles/common/tasks/main.yml       # Basis-System
2. roles/docker/tasks/main.yml       # Docker Installation  
3. roles/directories/tasks/main.yml  # Verzeichnisse erstellen
4. roles/dockge/tasks/main.yml       # Management Interface
5. roles/media/tasks/main.yml  # Media Services
6. roles/monitoring/tasks/main.yml   # Überwachung
7. roles/security/tasks/main.yml     # Sicherheit

Jede Rolle sollte enthalten:
- tasks/main.yml (Hauptaufgaben)
- handlers/main.yml (Services neustarten, etc.)
- templates/ (Konfigurationsdateien)
- defaults/main.yml (Standard-Variablen)
"