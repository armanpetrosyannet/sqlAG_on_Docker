# SQL Server 2019 Always On Availability Group on Docker

[![SQL Server](https://img.shields.io/badge/SQL%20Server-2019-CC2927?logo=microsoftsqlserver&logoColor=white)](https://www.microsoft.com/en-us/sql-server/sql-server-2019)
[![Docker](https://img.shields.io/badge/Docker-Compose-2496ED?logo=docker&logoColor=white)](https://docs.docker.com/compose/)
[![Ubuntu](https://img.shields.io/badge/Ubuntu-18.04-E95420?logo=ubuntu&logoColor=white)](https://releases.ubuntu.com/18.04/)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)

A fully scripted **3-node SQL Server 2019 Always On Availability Group** running on Docker — **no Active Directory, no Windows Server failover cluster, no domain controller**. Certificate-based endpoint authentication makes it truly domain-independent, which means you can spin up a production-like AG on a single laptop in minutes.

Perfect for **learning AG internals**, **testing failover scenarios**, **validating backup/restore strategies**, or building a **CI sandbox** for code that depends on read-only secondary replicas.

---

## Architecture

```
                ┌──────────────────────────────────────────────┐
                │           Docker bridge network              │
                │           172.22.224.0/24                    │
                │                                              │
   host:14331 ──┼──▶ sqlNode1 (172.22.224.21)  ── PRIMARY      │
   host:15021 ──┼──▶  endpoint :5022                           │
                │                                              │
   host:14332 ──┼──▶ sqlNode2 (172.22.224.22)  ── SECONDARY    │
   host:15022 ──┼──▶  endpoint :5022                           │
                │                                              │
   host:14333 ──┼──▶ sqlNode3 (172.22.224.23)  ── SECONDARY    │
   host:15023 ──┼──▶  endpoint :5022                           │
                │                                              │
                │   AG: CLUSTER_TYPE = NONE                    │
                │   Seeding: AUTOMATIC                         │
                │   Commit: ASYNCHRONOUS                       │
                └──────────────────────────────────────────────┘
```

| Node | Container | Internal IP | SQL Port (host) | Endpoint Port (host) |
|------|-----------|-------------|-----------------|----------------------|
| Primary   | `sqlNode1` | 172.22.224.21 | `14331` | `15021` |
| Secondary | `sqlNode2` | 172.22.224.22 | `14332` | `15022` |
| Secondary | `sqlNode3` | 172.22.224.23 | `14333` | `15023` |

---

## How it works

This setup combines three pieces that, together, get around the usual AG requirement of a Windows failover cluster or a Linux Pacemaker cluster:

1. **`CLUSTER_TYPE = NONE`** — the AG is created without any external clustering layer. Failover is manual, which is fine for a lab.
2. **Certificate-based endpoint authentication** — `command.sql` generates a database master key and a `dbm_certificate` shared across all three nodes, so replicas trust each other without Kerberos or AD.
3. **Static IPs and `extra_hosts`** — each container gets a fixed IP on a user-defined bridge network and a hosts-file entry for its peers, so `sqlNode1.lab.local`, `sqlNode2.lab.local`, `sqlNode3.lab.local` resolve correctly inside the AG configuration.

The `setup.bat` script builds the base image, runs `command.sql` inside a throwaway container to bake in the certificate and HADR endpoint, then commits the result as `sql2019_alwayson_node` — the image used by all three replicas in `docker-compose.yml`.

---

## Quick start

### Prerequisites

- Docker Desktop (Windows / macOS) or Docker Engine + Docker Compose (Linux)
- ~4 GB free RAM (SQL Server is hungry)
- `sqlcmd` available locally — required for `setup.bat` (comes with [SQL Server Command Line Utilities](https://learn.microsoft.com/en-us/sql/tools/sqlcmd/sqlcmd-utility))

### 1. Build the AG-ready image

```bash
git clone https://github.com/armanpetrosyannet/sqlAG_on_Docker.git
cd sqlAG_on_Docker
setup.bat
```

This will:
- Build `sql2019_alwayson` from the Dockerfile
- Spin up a temporary container, run `command.sql` to provision the certificate and HADR endpoint
- Commit the result as `sql2019_alwayson_node`

### 2. Launch the 3-node cluster

```bash
docker-compose up -d
```

You should now have `sqlNode1`, `sqlNode2`, and `sqlNode3` running on the `internal` bridge network.

### 3. Fix the SQL `@@SERVERNAME` on each node

Containers inherit the image's original machine name, so each replica needs to be re-registered with its actual hostname. Run this **on each container**:

```sql
DECLARE @newName VARCHAR(80);
SET @newName = CONVERT(VARCHAR(80), SERVERPROPERTY('MachineName'));
EXEC sp_dropserver @@SERVERNAME;
EXEC sp_addserver @newName, 'local';
```

Then restart the containers:

```bash
docker-compose restart
```

### 4. Create the Availability Group on the primary

Connect to `sqlNode1` (`localhost,14331`) and run:

```sql
CREATE AVAILABILITY GROUP [AG1]
WITH (CLUSTER_TYPE = NONE)
FOR REPLICA ON
    N'sqlNode1' WITH (
        ENDPOINT_URL = N'TCP://sqlNode1.lab.local:5022',
        FAILOVER_MODE = MANUAL,
        AVAILABILITY_MODE = ASYNCHRONOUS_COMMIT,
        SEEDING_MODE = AUTOMATIC,
        SECONDARY_ROLE (ALLOW_CONNECTIONS = ALL)
    ),
    N'sqlNode2' WITH (
        ENDPOINT_URL = N'TCP://sqlNode2.lab.local:5022',
        FAILOVER_MODE = MANUAL,
        AVAILABILITY_MODE = ASYNCHRONOUS_COMMIT,
        SEEDING_MODE = AUTOMATIC,
        SECONDARY_ROLE (ALLOW_CONNECTIONS = ALL)
    ),
    N'sqlNode3' WITH (
        ENDPOINT_URL = N'TCP://sqlNode3.lab.local:5022',
        FAILOVER_MODE = MANUAL,
        AVAILABILITY_MODE = ASYNCHRONOUS_COMMIT,
        SEEDING_MODE = AUTOMATIC,
        SECONDARY_ROLE (ALLOW_CONNECTIONS = ALL)
    );
GO
```

### 5. Join the secondaries

On both `sqlNode2` and `sqlNode3`:

```sql
ALTER AVAILABILITY GROUP [AG1] JOIN WITH (CLUSTER_TYPE = NONE);
GRANT ALTER ANY DATABASE TO [dbm_login];
ALTER AVAILABILITY GROUP [AG1] GRANT CREATE ANY DATABASE;
```

### 6. Add a database

On the primary:

```sql
CREATE DATABASE TestDB;
ALTER DATABASE TestDB SET RECOVERY FULL;
BACKUP DATABASE TestDB TO DISK = '/var/opt/mssql/data/TestDB.bak';
ALTER AVAILABILITY GROUP [AG1] ADD DATABASE TestDB;
```

With `SEEDING_MODE = AUTOMATIC`, the database will replicate to both secondaries automatically.

---

## Verifying the AG

Connect to any replica with SSMS, expand **Always On High Availability → Availability Groups → AG1**, and open the dashboard. Or run:

```sql
SELECT
    ag.name AS ag_name,
    ar.replica_server_name,
    ars.role_desc,
    ars.synchronization_health_desc,
    ars.connected_state_desc
FROM sys.availability_groups ag
JOIN sys.availability_replicas ar       ON ag.group_id = ar.group_id
JOIN sys.dm_hadr_availability_replica_states ars ON ar.replica_id = ars.replica_id;
```

You should see one `PRIMARY` and two `SECONDARY` replicas, all `HEALTHY` and `CONNECTED`.

---

## Repository layout

| File | What it does |
|------|--------------|
| `Dockerfile` | Ubuntu 18.04 + SQL Server 2019 with `hadr.hadrenabled = 1` |
| `command.sql` | Master key, certificate, HADR endpoint on port 5022 |
| `setup.bat` | Builds the image, bakes in the cert, commits `sql2019_alwayson_node` |
| `docker-compose.yml` | 3-node bridge network with static IPs and shared certificate volume |

---

## Caveats

- **`CLUSTER_TYPE = NONE` AGs do not support automatic failover.** Failover is always manual (`ALTER AVAILABILITY GROUP ... FAILOVER`). For automatic failover you need a Pacemaker cluster on Linux or WSFC on Windows.
- **Read-scale workload only.** This configuration is great for offloading reads and for learning, but it is not an HA solution in the strict sense — there is no quorum and no fencing.
- **The SA password is hard-coded** to `PaSSw0rd` for convenience. Change `SA_PASSWORD` in the `Dockerfile` and `MSSQL_SA_PASSWORD` in `docker-compose.yml` before exposing this anywhere outside your laptop.
- **Ubuntu 18.04 is out of standard support.** For a longer-lived setup, bump the base image to 20.04 or 22.04 and update the Microsoft repo accordingly.

---

## Why this exists

Spinning up a multi-node AG traditionally means several Windows VMs, a domain controller, and a Windows Server Failover Cluster — hours of setup just to test a query plan on a secondary or rehearse a failover. This repo collapses that to a single `docker-compose up`, which is invaluable when you want to:

- Reproduce a redo-thread or sync-lag issue in isolation
- Test application connection-string routing (`ApplicationIntent=ReadOnly`)
- Validate scripts that rely on `sys.dm_hadr_*` DMVs
- Train new DBAs on AG mechanics without provisioning a lab domain

---

## License

MIT — do whatever you want with it. Contributions and issues welcome.

## Author

**Arman Petrosyan** — Senior DBA & Software Engineer
[GitHub](https://github.com/armanpetrosyannet)