# Gitea Docker Compose Setup

This directory contains a complete Docker Compose setup for running a self-hosted Gitea instance with PostgreSQL database and automated backups.

## Overview

The setup includes:
- **Gitea** - Self-hosted Git service (v1.26)
- **PostgreSQL** - Database backend (v15-alpine)
- **Backup Scheduler** - Automated daily backups with 7-day retention

## Quick Start

### Prerequisites
- Docker and Docker Compose installed
- At least 2GB free disk space

### 1. Initial Setup

Clone or navigate to this directory:
```bash
cd gitea
```

### 2. Configure Database Password

**Important:** Change the default database password before running for the first time.

Edit `docker-compose.yaml` and update:
- Line 16: `POSTGRES_PASSWORD=SuperSecretDatabasePassword` → your secure password
- Line 36: `GITEA__database__PASSWD=SuperSecretDatabasePassword` → same password

### 3. Start Services

```bash
docker compose up -d
```

The containers will start and initialize:
- Database container performs health checks before Gitea starts
- Gitea initializes on first run
- Backup scheduler starts (runs daily at 2:00 AM)

### 4. Access Gitea

Open your browser and navigate to:
```
http://localhost:3000
```

**First Login:**
- Admin credentials can be set during initial setup
- Complete the installation wizard

## Service Details

### Gitea Web & Git Access

| Service | Port | Purpose |
|---------|------|---------|
| Web UI | 3000 | Gitea web interface |
| SSH Git | 2222 | Clone/push via SSH |

**Example SSH clone:**
```bash
git clone ssh://git@localhost:2222/username/repo.git
```

### Database Container
- **Image:** postgres:15-alpine
- **Container:** gitea_db
- **Database:** gitea
- **User:** gitea
- **Health Check:** Enabled (10s interval)

### Backup Scheduler

The backup container runs a cron job daily at **2:00 AM** that:
1. Creates a full Gitea dump (database + repositories)
2. Saves it to `./gitea_backups/` directory
3. Deletes backups older than 7 days

**Backup files format:** `gitea-dump-YYYY-MM-DD.zip`

## Volumes & Storage

| Volume | Mount Point | Purpose |
|--------|-------------|---------|
| `gitea_data` | `/data` in gitea | Repositories, configuration, avatars |
| `postgres_data` | `/var/lib/postgresql/data` in db | Database files |
| `./gitea_backups` | `/backup` in backup service | Backup storage (host directory) |

## Timezone Configuration (Optional)

To set a specific timezone, uncomment the `TZ` environment variables in `docker-compose.yaml`:

```yaml
environment:
  - TZ=Europe/London  # or your timezone
```

## Restoring from Backup

### Prerequisites
- Backup file (`.zip` format)
- Running Docker and Docker Compose

### Restore Steps

Run the restore script with the backup file path:

```bash
./restore.sh /path/to/gitea-dump-YYYY-MM-DD.zip
```

**Examples:**
```bash
# Backup in current directory
./restore.sh ./gitea-dump-2026-06-09.zip

# Backup in parent directory
./restore.sh ../backups/gitea-dump-2026-06-09.zip

# Absolute path
./restore.sh /home/user/backups/gitea-dump-2026-06-09.zip
```

### What the Restore Script Does

The restore process is **fully automated** and performs these steps:

1. **Stops** the Gitea application (database remains running)
2. **Extracts** the backup file to a temporary workspace
3. **Wipes** the existing database schema and reimports the backup SQL
4. **Restores** all file volumes (repositories, configuration, avatars)
5. **Restarts** all services and brings Gitea back online

### Safety Features

- **User confirmation required** before proceeding (the script warns about data overwrite)
- **Validates** backup file exists before starting
- **Automatic cleanup** of temporary files
- **Error checking** at each step
- **Database health verification** before restoration

### Example Restore Session

```
$ ./restore.sh ../downloads/gitea-dump-2026-06-09.zip

=================================================================
WARNING: This script will OVERWRITE your existing Gitea data!
Target Backup: /home/user/downloads/gitea-dump-2026-06-09.zip
=================================================================
Are you absolutely sure you want to proceed? (y/N): y

--> Stopping Gitea application container (keeping database alive)...
--> Creating temporary workspace...
--> Extracting backup file...
--> Wiping existing database schema...
--> Importing backup SQL into database...
--> Restoring file volumes...
--> Restarting all Gitea services...

=================================================================
 SUCCESS: Gitea has been restored from: gitea-dump-2026-06-09.zip
=================================================================
```

## Troubleshooting

### Gitea won't start
```bash
# Check logs
docker compose logs gitea

# Verify database is healthy
docker compose logs db
```

### Database connection refused
- Verify `POSTGRES_PASSWORD` matches in both services
- Ensure database container has passed health check
- Check network connectivity: `docker network ls`

### Backup not running
- Verify backup container is running: `docker compose ps`
- Check cron logs: `docker compose logs backup`
- Ensure `./gitea_backups` directory exists and is writable

### Restore script fails
- Verify backup file exists: `ls -lh /path/to/backup.zip`
- Check if Gitea container is running: `docker compose ps`
- Review script output for specific error messages
- Ensure sufficient disk space for extraction

### Permission denied errors
- Run with appropriate permissions (may need `sudo`)
- Ensure volumes are writable by Docker

## Backup Management

### Manual Backup

To create an on-demand backup without waiting for the scheduled job:

```bash
docker exec -u git gitea gitea dump -c /data/gitea/conf/app.ini -f /tmp/gitea-dump-manual.zip
docker exec gitea sh -c 'mv /tmp/gitea-dump-manual.zip /backup/.'
```

### List Backups

```bash
ls -lh ./gitea_backups/
```

### Manual Backup Cleanup

Remove backups older than a specific date:
```bash
find ./gitea_backups -name "gitea-dump-*.zip" -mtime +7 -delete
```

## Security Considerations

- **Change default passwords** before production use
- **Use strong PostgreSQL password** (not the example)
- **Restrict SSH port** (2222) access if exposed to internet
- **Regular backups** are enabled by default (verify they're running)
- **Monitor logs** for unusual activity
- **Use HTTPS** in production (configure reverse proxy like nginx)

## Maintenance

### Stop Services
```bash
docker compose stop
```

### Start Services
```bash
docker compose start
```

### Restart Services
```bash
docker compose restart
```

### Remove All Containers & Volumes (Destructive)
```bash
docker compose down -v
```

### View Logs
```bash
# All services
docker compose logs -f

# Specific service
docker compose logs -f gitea
docker compose logs -f db
docker compose logs -f backup
```

## Useful Commands

### Access Gitea Database Directly
```bash
docker exec -it gitea_db psql -U gitea -d gitea
```

### Execute Commands in Gitea Container
```bash
docker exec -it gitea /bin/bash
```

### Check Container Resource Usage
```bash
docker stats
```

## Additional Resources

- [Gitea Documentation](https://docs.gitea.io/)
- [PostgreSQL Documentation](https://www.postgresql.org/docs/)
- [Docker Compose Reference](https://docs.docker.com/compose/compose-file/)

## License

This setup is provided as-is for self-hosting purposes.
