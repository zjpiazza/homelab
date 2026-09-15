-- Local root is reserved for in-pod administration and probes.
-- Use this tailnet-only administrator to provision per-project databases/users.
GRANT ALL PRIVILEGES ON *.* TO 'dolt-admin'@'%' WITH GRANT OPTION;
