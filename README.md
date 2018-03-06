# MariaDB Galera Cluster Sandbox

This repo provides a CentOS 7 based MariaDB Galera Cluster sandbox. In this sandbox there are three MariaDB servers:

* db1.example.lan with the IP 192.168.33.11
* db2.example.lan with the IP 192.168.33.12
* db3.example.lan with the IP 192.168.33.13

You can add more if you want but three should be enough. Every server is a master servers. Changes (INSERT, UPDATE, CREATE, ALTER etc) on one of them are replicated in (nearly) realtime across all others on row level.

In a perfect world you would now enter one or all three IPs into your applications and the connector would pick one server. However if one server is out for maintenance you application would stop working. The better approach is a floating IP. That IP would point to one working server.   
So I added a keepalived daemon to provide a floating IP. In this sandbox it's hardcoded to `192.168.33.2`. One of the three servers should obtain this IP address. If the server with that floating IP goes down another one will obtain it quickly.

**Note**: It's not a seamless failover. When the failover IP switches host the connection will be reset and the current transaction will be lost. However most connectors will automatically deal with that.

## Requirements

You need the following:
* A working {vagrant,virtualbox,ansible} environment
* Basic knowledge about MySQL, Linux and IP Routing
* 4 CPU cores
* 8 GByte RAM

Vagrant and ansible experience is recommended.

## Setup

Start the CentOS 7 virtual machines with `vagrant up`. After this is done run ansible to enslave them as database servers with `ansible-playbook site.yml`.

**Note**: Depending on your network speed the task "Installing mariadb-server" can take a little bit. I was downloading with 160 kBit/s.

You now have a working Galera Cluster running waiting for your queries. To rebuild the whole sandbox run `vagrant destroy -f` and start over again.

## Looking around

Login onto a database server via ssh: `vagrant ssh db1` for example. You can become root with `su`. The root password is `vagrant`.

To get a MySQL prompt use `mysql` as root. Btw: The MySQL root password is `supersecret`.

You can stop servers with `vagrant halt db3` and start them again with `vagrant up db3`.

### Who has the failover IP

To see which server currently has the failover IP use the playbook: `ansible-playbook who-has-the-failover-ip.yml`.

The output should look like this:
```
TASK [Who has it?] *************************************************************************************************************************************************************************************************************************************************************
skipping: [db2.example.lan]
skipping: [db3.example.lan]
ok: [db1.example.lan] => {
    "msg": "I've the failover IP!"
}
```

## Testing around

### Sample large database

The GitHub User **datacharmer** has provided a git Repository containing a large MySQL Database Dump for testing. I forked that and exchanged MyISAM with InnoDB: https://github.com/vlcty/test_db

Download the test database onto the server and follow the README instructions.

### Testing the failover IP

To check if the failover IP is transferred to another server find out which server currently has it. For example I get this result:

```
skipping: [db1.example.lan]
skipping: [db2.example.lan]
ok: [db3.example.lan] => {
    "msg": "I've the failover IP!"
}
```

Now shutdown that node. In my case it's db3 (`vagrant halt db3`). Now check again which server has it. The result should look like:

```
skipping: [db1.example.lan]
ok: [db2.example.lan] => {
    "msg": "I've the failover IP!"
}
```

Note: db3 won't show up here, because the server is not reachable. The IP was transferred from `db3` to `db2`. Works!

## Add more servers

You can install as many servers as you like. Open the file `inventory` and add more lines. You also have to edit the file `Vagrantfile`.   
Both files are self explaining.

## Further reading

Developed based on:
https://linuxadmin.io/galeria-cluster-configuration-centos-7/
