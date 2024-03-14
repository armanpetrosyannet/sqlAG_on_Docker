# SQL Server 2019 Always On Availability Group on Docker Cluster

This repository provides scripts and configurations for setting up SQL Server 2019 Always On Availability Group on a Docker cluster with domain independence.

## Overview

The project allows you to deploy SQL Server 2019 instances in Docker containers and configure them into an Always On Availability Group. This setup ensures high availability and disaster recovery for SQL Server databases.

## Prerequisites

Before starting, ensure you have the following:
- Docker installed on each node of the cluster.
- Basic understanding of Docker Swarm or Kubernetes for cluster management.
- Familiarity with SQL Server Always On Availability Groups.
- Access to domain-independent configurations or tools for managing domain-independent setups.

## Installation and Setup

1. Clone this repository to your Docker cluster manager node.
2. Modify the Dockerfile or Docker Compose file to include necessary configurations for SQL Server 2019.
3. Build the Docker images for SQL Server instances using the provided Dockerfile.
4. Deploy SQL Server containers on each node of the Docker cluster.
5. Configure the Docker containers to communicate with each other and form a SQL Server Always On Availability Group.

## Usage

1. Execute `setup.bat` to build Docker images, run containers, and execute SQL commands.
2. Use `Docker-Compose.yml` to create primary and secondary nodes for the Availability Group cluster.
3. Customize configurations and environment variables as per your requirements.

After running `docker-compose up`, you will have three running SQL Server instances. To ensure unique names for each SQL Server instance based on the hostname set in the Docker-Compose.yml file, execute the following SQL script on each running container:

```sql
DECLARE @newName VARCHAR(80);
SET @newName = CONVERT(VARCHAR(80), SERVERPROPERTY('MachineName'));
EXEC sp_dropserver @@SERVERNAME;
EXEC sp_addserver @newName, 'local';
```
Restart the containers to apply the changes.

Once the container names are updated, execute the following SQL script to create the Availability Group (AG) and join the secondary replicas:

```sql
CREATE AVAILABILITY GROUP [AG1]
WITH (
    CLUSTER_TYPE = NONE
)
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
After creating the AG, execute the following command on each secondary replica to change the cluster type:
```sql
ALTER AVAILABILITY GROUP [AG1] JOIN WITH (CLUSTER_TYPE = NONE);
```
## To check the availability group status using SQL Server Management Studio (SSMS), you can use the following steps:

Open SQL Server Management Studio and connect to one of the SQL Server instances in your Availability Group.

Once connected, navigate to the "Object Explorer" pane on the left-hand side.

Expand the server tree, then expand the "Always On High Availability" node.

Under the "Availability Groups" folder, you should see your availability group listed. Right-click on your availability group and select "Show Dashboard".

The dashboard provides a graphical overview of your availability group's health, synchronization status, and other relevant information.

Alternatively, you can run the following query in a new query window to retrieve the availability group status:
