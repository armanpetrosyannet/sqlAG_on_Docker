USE master
GO

CREATE LOGIN dbm_login WITH PASSWORD = 'Password1';
CREATE USER dbm_user FOR LOGIN dbm_login;
GO

CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'Password1';
go
CREATE CERTIFICATE dbm_certificate WITH SUBJECT = 'dbm';
BACKUP CERTIFICATE dbm_certificate
TO FILE = '/usr/certificate/dbm_certificate.cer'
WITH PRIVATE KEY (
      FILE = '/usr/certificate/dbm_certificate.pvk',
      ENCRYPTION BY PASSWORD = 'Password1'
   );
GO

CREATE ENDPOINT [Hadr_endpoint]
   AS TCP (LISTENER_IP = all, LISTENER_PORT = 5022)
   FOR DATA_MIRRORING (
      ROLE = ALL,
      AUTHENTICATION = CERTIFICATE dbm_certificate,
      ENCRYPTION = REQUIRED ALGORITHM AES
      );
ALTER ENDPOINT [Hadr_endpoint] STATE = STARTED;
GRANT CONNECT ON ENDPOINT::[Hadr_endpoint] TO [dbm_login];

ALTER EVENT SESSION  AlwaysOn_health ON SERVER WITH (STARTUP_STATE=ON);
GO