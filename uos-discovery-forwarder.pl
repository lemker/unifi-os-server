#!/usr/bin/perl

# Broadcast device discovery from 10002 to 10001 on loopback so uos-discovery-client receives it
# Docker forwards published ports as unicast, which only reaches one of the 10001 listeners
# Usage: uos-discovery-forwarder [listen port] [target host:port], Kubernetes uses it as a host network relay

use strict;
use warnings;
use IO::Select;
use IO::Socket::INET;

$| = 1;

# Exit on stop so the port is freed right away, PID 1 ignores signals without a handler
# The image stops with SIGRTMIN+3 (NUM37) for systemd
$SIG{TERM} = $SIG{INT} = $SIG{NUM37} = sub { exit 0 };

my $listen_port = $ARGV[0] // 10002;
my ($target_host, $target_port) = split /:/, ($ARGV[1] // '127.255.255.255:10001');

my $target_addr = inet_aton($target_host) or die "Unable to resolve $target_host\n";
my $target = sockaddr_in($target_port, $target_addr);

my $in = IO::Socket::INET->new(Proto => 'udp', LocalAddr => '0.0.0.0', LocalPort => $listen_port, ReuseAddr => 1)
    or die "Unable to listen on udp $listen_port: $!\n";
my $out = IO::Socket::INET->new(Proto => 'udp', Broadcast => 1)
    or die "Unable to open broadcast socket: $!\n";

print "Forwarding discovery from udp $listen_port to $target_host:$target_port\n";

# Log each device at most every 10 seconds
my %last_logged;

# Wait at most a second at a time, signal handlers only run between calls
my $select = IO::Select->new($in);

while (1) {
    next unless $select->can_read(1);
    my $packet;
    my $sender = $in->recv($packet, 2048) or next;
    $out->send($packet, 0, $target);

    my $ip = inet_ntoa((sockaddr_in($sender))[1]);

    # Fields after the 4 byte header: type (1 byte), length (2 bytes), value
    my %fields;
    my $offset = 4;
    while ($offset + 3 <= length $packet) {
        my ($type, $length) = unpack 'Cn', substr($packet, $offset, 3);
        last if $offset + 3 + $length > length $packet;
        $fields{$type} //= substr($packet, $offset + 3, $length);
        $offset += 3 + $length;
    }
    my $mac = length($fields{0x01} // '') == 6 ? join(':', unpack '(H2)6', $fields{0x01}) : 'unknown';
    my $name = $fields{0x0B} // 'unknown';
    my $model = $fields{0x14} // $fields{0x0C} // 'unknown';

    my $now = time;
    if (($last_logged{"$ip $mac"} // 0) <= $now - 10) {
        $last_logged{"$ip $mac"} = $now;
        print "Forwarded discovery from $ip: $name ($model, $mac)\n";
    }
}
