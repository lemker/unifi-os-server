#!/usr/bin/perl

# Broadcast device discovery from 10002 to 10001 on loopback so uos-discovery-client receives it
# Docker forwards published ports as unicast, which only reaches one of the 10001 listeners
# Usage: uos-discovery-forwarder [listen port] [target host:port], Kubernetes uses it as a host network relay

use strict;
use warnings;
use IO::Socket::INET;

$| = 1;

my $listen_port = $ARGV[0] // 10002;
my ($target_host, $target_port) = split /:/, ($ARGV[1] // '127.255.255.255:10001');

my $target_addr = inet_aton($target_host) or die "Unable to resolve $target_host\n";
my $target = sockaddr_in($target_port, $target_addr);

my $in = IO::Socket::INET->new(Proto => 'udp', LocalAddr => '0.0.0.0', LocalPort => $listen_port)
    or die "Unable to listen on udp $listen_port: $!\n";
my $out = IO::Socket::INET->new(Proto => 'udp', Broadcast => 1)
    or die "Unable to open broadcast socket: $!\n";

print "Forwarding discovery from udp $listen_port to $target_host:$target_port\n";

while (1) {
    my $packet;
    $in->recv($packet, 2048) or next;
    $out->send($packet, 0, $target);
}
