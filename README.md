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

### Create a new user

Create a new user with the name `auser` with password `auser` and a new database `myapplication`:

```
MariaDB [(none)]> CREATE USER 'auser'@'%'IDENTIFIED BY 'auser';
Query OK, 0 rows affected (0.01 sec)

MariaDB [(none)]> CREATE DATABASE myapplication;
Query OK, 1 row affected (0.01 sec)

MariaDB [(none)]> GRANT ALL ON myapplication TO auser;
Query OK, 0 rows affected (0.01 sec)

MariaDB [(none)]> FLUSH PRIVILEGES;
Query OK, 0 rows affected (0.00 sec)
```

You should now be able to log in from a third machine:

```
:-$ mysql -h 192.168.33.2 -u auser -p myapplication;
Enter password:
Welcome to the MySQL monitor.  Commands end with ; or \g.
Your MySQL connection id is 22
Server version: 5.5.5-10.2.13-MariaDB MariaDB Server

Copyright (c) 2000, 2018, Oracle and/or its affiliates. All rights reserved.

Oracle is a registered trademark of Oracle Corporation and/or its
affiliates. Other names may be trademarks of their respective
owners.

Type 'help;' or '\h' for help. Type '\c' to clear the current input statement.

mysql>
```

Now shutdown the server with the active failover IP configured and watch what happens. Will we receive a disconnect or will the connection be smoothly migrated to a new host?

Solution (active was db2):
```
:-$ vagrant halt db2
==> db2: Attempting graceful shutdown of VM...
```

My MySQL connection after the next Statement:
```
mysql> SHOW TABLES;
ERROR 2013 (HY000): Lost connection to MySQL server during query

mysql> SHOW TABLES;
ERROR 2006 (HY000): MySQL server has gone away
No connection. Trying to reconnect...
Connection id:    11
Current database: myapplication

Empty set (0,01 sec)
```

Damn! Looks like that doesn't work as smooth as expected. But there is also a good news. The modern connectors can handle that without user interaction.

### Testing Perls DBD::mysql mysql_auto_reconnect option

The Perl module `DBD::mysql` provides the connection option `mysql_auto_reconnect`. According to the documentation this should reconnect to the database if a disconnect occures.   
In this repo there is a perl script perl-connection-test.pl. To run it please do the creation steps mentioned in "Create a new user" first.


Afterwards run the script. It should look like this:
```
:-$ perl perl-connection-test.pl
Log: Please create the database and the user first! See README for details.

Log: Connected to the database!
Log: Dropped database connectionTest
Log: Recreated table connectionTest
Log: Statement prepared!
Log: First statement was executed!
Now kill the server with the floating IP! Hit enter afterwards
```

At this point the scripts waits with an open connection. The database table currently should look like this:

```
MariaDB [myapplication]> SELECT * FROM connectionTest;
+----+-----------------------------------------------+
| id | message                                       |
+----+-----------------------------------------------+
|  6 | I was inserted before the connection was lost |
+----+-----------------------------------------------+
1 row in set (0.00 sec)
```

Now find out which server we are currently connected to via the floating IP:

```
:~$ ansible-playbook who-has-the-failover-ip.yml

[...]

TASK [Who has it?]
##################################
skipping: [db2.example.lan]
skipping: [db3.example.lan]
ok: [db1.example.lan] => {
    "msg": "I've the failover IP!"
}
```

In my example `db1` is currently active. Kill it!

```
:~$ vagrant halt db1
```

Wait a few seconds. Now hit enter so the script would continue:

```
Log: Second statement was executed!
Log: If you see this message your application survived the outage without only one additional line of code. I just turned on the mysql_auto_reconnect feature! Grab a beer now! You have earned it!
```

Looks great! A quick look into the database:

```
MariaDB [myapplication]> SELECT * FROM connectionTest;
+----+-----------------------------------------------+
| id | message                                       |
+----+-----------------------------------------------+
|  6 | I was inserted before the connection was lost |
|  9 | I was inserted after the connection was lost  |
+----+-----------------------------------------------+
2 rows in set (0.00 sec)
```

Very nice! Just one option passed into the `connect`-function and we mitigated a connection loss without great changes to the logic. However this won't work with a open transaction.

### Checking out the replication

First on one server we create a database and use it.

```
MariaDB [(none)]> CREATE DATABASE stuff; USE stuff;
Query OK, 1 row affected (0.00 sec)

Database changed
MariaDB [stuff]>
```

Then we create a table there:

```
MariaDB [stuff]> CREATE TABLE numbers(id INT UNSIGNED NOT NULL AUTO_INCREMENT, aNumber INT UNSIGNED NOT NULL, PRIMARY KEY(id));
Query OK, 0 rows affected (0.01 sec)
```

Then we insert some data:

```
MariaDB [stuff]> INSERT INTO numbers (aNumber) SELECT COALESCE(MAX(aNumber) + 1, 1) FROM numbers;
Query OK, 1 row affected (0.01 sec)
Records: 1  Duplicates: 0  Warnings: 0

MariaDB [stuff]>
MariaDB [stuff]> INSERT INTO numbers (aNumber) SELECT COALESCE(MAX(aNumber) + 1, 1) FROM numbers;
Query OK, 1 row affected (0.01 sec)
Records: 1  Duplicates: 0  Warnings: 0
```

Now we should have two entries:

```
MariaDB [stuff]> SELECT * FROM numbers;
+----+---------+
| id | aNumber |
+----+---------+
|  5 |       1 |
|  8 |       2 |
+----+---------+
2 rows in set (0.00 sec)
```

The first thing I found out is that the IDs are not sequential. Interesting! Now let's have a look at another server. Is there the same data? The answer should be *yes*.

### Locking tables

Is a LOCK TABLES statement on one server distributed?

On db1:
```
MariaDB [stuff]> LOCK TABLE numbers WRITE;
Query OK, 0 rows affected (0.00 sec)
```

Now only the session on db1 should be able to write to the table.

On db2:
```
MariaDB [stuff]> INSERT INTO numbers (aNumber) SELECT COALESCE(MAX(aNumber) + 1, 1) FROM numbers;
Query OK, 1 row affected (0.01 sec)
Records: 1  Duplicates: 0  Warnings: 0

MariaDB [stuff]> SELECT * FROM numbers;
+----+---------+
| id | aNumber |
+----+---------+
|  5 |       1 |
|  8 |       2 |
| 13 |       3 |
+----+---------+
3 rows in set (0.00 sec)
```

Well, that worked. So a lock is not distributed. But is the data on db1, too?

On db1:
```
MariaDB [stuff]> SELECT * FROM numbers;
+----+---------+
| id | aNumber |
+----+---------+
|  5 |       1 |
|  8 |       2 |
+----+---------+
2 rows in set (0.00 sec)
```

Well, the data is not there. Is it already broken? What happens when the lock is removed?

On db1:
```
MariaDB [stuff]> UNLOCK TABLES;
Query OK, 0 rows affected (0.00 sec)

MariaDB [stuff]> SELECT * FROM numbers;
+----+---------+
| id | aNumber |
+----+---------+
|  5 |       1 |
|  8 |       2 |
| 13 |       3 |
+----+---------+
3 rows in set (0.00 sec)
```

Oh wow. The data appeared. So nothing was lost. Interesting. Remember: Every node is a master server. The is no master/slave setup.

### Transactions

So locks are not distributed. How about transactions?

On db1:
```
MariaDB [stuff]> SELECT * FROM numbers;
+----+---------+
| id | aNumber |
+----+---------+
|  5 |       1 |
|  8 |       2 |
| 13 |       3 |
+----+---------+
3 rows in set (0.00 sec)

MariaDB [stuff]> BEGIN;
Query OK, 0 rows affected (0.00 sec)

MariaDB [stuff]> INSERT INTO numbers (aNumber) SELECT COALESCE(MAX(aNumber) + 1, 1) FROM numbers;
Query OK, 1 row affected (0.00 sec)
Records: 1  Duplicates: 0  Warnings: 0
```

I would assume there is no value 4 in the database on db2. Let's check that:
```
MariaDB [stuff]> SELECT * FROM numbers;
+----+---------+
| id | aNumber |
+----+---------+
|  5 |       1 |
|  8 |       2 |
| 13 |       3 |
+----+---------+
3 rows in set (0.00 sec)
```

No value 4 there. What happens when I delete everything on db2 now?

```
MariaDB [stuff]> TRUNCATE numbers;
Query OK, 0 rows affected (0.01 sec)

MariaDB [stuff]> SELECT * FROM numbers;
Empty set (0.00 sec)
```

As expected: The table is empty now. Now let's commit on db1:

```
MariaDB [stuff]> COMMIT;
ERROR 1213 (40001): Deadlock: wsrep aborted transaction

MariaDB [stuff]> SELECT * FROM numbers;
Empty set (0.00 sec)
```

So my transaction was killed. Transactions are therefore not replicated.

## Add more servers

You can install as many servers as you like. Open the file `inventory` and add more lines. You also have to edit the file `Vagrantfile`.   
Both files are self explaining.

## Further reading

Developed based on:
https://linuxadmin.io/galeria-cluster-configuration-centos-7/

Limitations using a Galera Cluster:
http://galeracluster.com/documentation-webpages/limitations.html

Monitoring a Galera Cluster:
http://galeracluster.com/documentation-webpages/monitoringthecluster.html
