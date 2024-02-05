# This is the setup guide for the Kubernetes Master Server (Control plane)

#DO NOT USE THIS GUIDE YET!
Everything you will find here is a work in progress and has not been tested as of now

1) Hostnames
You can use the hostname(s) you have on your Debian server(s), or workstation(s) acting as a server.
It is recommended that you use static IP addresses. An easy way to do this is to use your local DNS server (for many this will be their router). Some examples of how to do that will be linked here in a little bit of time :)

1.a) How to find your hostname if you do not know it?
Open a terminal window and print
$ hostname  (without the $. It is for illustration purposes :)


1.b) Set Host Name and update hosts file if you need it
Login to each node (master & woker nodes) and set their hostname using hostnamectl command.

$ sudo hostnamectl set-hostname "k8s-master.linuxtechi.local"      // Run on master node
$ sudo hostnamectl set-hostname "k8s-worker01.linuxtechi.local"    // Run on 1st worker node
$ sudo hostnamectl set-hostname "k8s-worker02.linuxtechi.local"    // Run on 2nd worker node
Also add the following entries in /etc/hosts file on all the nodes,

192.168.1.23   k8s-master.linuxtechi.local     k8s-master
192.168.1.24   k8s-worker01.linuxtechi.local   k8s-worker01
192.168.1.25   k8s-worker02.linuxtechi.local   k8s-worker02

