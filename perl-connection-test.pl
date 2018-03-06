#!/usr/bin/perl
use strict;
use DBI;

my $dbh = undef;
my $stm = undef;

sub printLog {
    printf("Log: %s\n", shift);
}

sub connectToDatabase {
    $dbh = DBI->connect('DBI:mysql:database=myapplication;host=192.168.33.2',
        'auser', 'auser', { RaiseError => 1, mysql_auto_reconnect => 1})
        or die('Was not able to connect to the database!');

    printLog('Connected to the database!');
}

sub createTable {
    $dbh->do('DROP TABLE IF EXISTS connectionTest');

    printLog('Dropped database connectionTest');

    $dbh->do('CREATE TABLE connectionTest (id INT UNSIGNED NOT NULL AUTO_INCREMENT, message VARCHAR(255) NOT NULL, PRIMARY KEY (id))');

    printLog('Recreated table connectionTest');
}

sub prepareStatement {
    $stm = $dbh->prepare('INSERT INTO connectionTest (message) VALUES(?)');

    printLog('Statement prepared!');
}

sub insertRow {
    $stm->execute(sprintf('I was inserted %s the connection was lost', shift));

    printLog(sprintf('%s statement was executed!', shift));
}

sub insertFirstRow {
    insertRow('before', 'First');
}

sub insertSecondRow {
    insertRow('after', 'Second');
}

sub waitForUserToKillTheServer {
    print('Now kill the server with the floating IP! Hit enter afterwards');
    <STDIN>;
}

sub main {
    printLog("Please create the database and the user first! See README for details.\n");

    connectToDatabase();
    createTable();
    prepareStatement();
    insertFirstRow();
    waitForUserToKillTheServer();
    insertSecondRow();

    printLog('If you see this message your application survived the outage without only one additional line of code. I just turned on the mysql_auto_reconnect feature! Grab a beer now! You have earned it!');
}

main();
