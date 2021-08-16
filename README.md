# migrate

A Puppet Task to migrate a Puppet Agent to a new Puppet Master.

## Description

This modules provides a Puppet Task to migrate a Puppet Agent to a new Puppet Master.

See references for more information about parameters and usage.

The module will perform the following actions:

1. Verify the node can reach the new Puppet Master and CA Server.
2. Get current setting for server and ca_server from puppet.conf.
3. Backup $ssldir
4. Set $server and $ca_server to new values.
5. Run puppet agent using new settings.
6. Restore $ssldir and original settings if error occurs.

This module also provide a Puppet plan to upgrade puppet before migration. See `migrate::upgrade_and_migrate` for more information.
