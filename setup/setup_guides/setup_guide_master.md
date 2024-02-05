# This is the setup guide for the Kubernetes Master Server (Control plane)

#DO NOT USE THIS GUIDE YET!
Everything you will find here is a work in progress and has not been tested as of now

1) Hostnames
You can use the hostname(s) you have on your Debian server(s), or workstation(s) acting as a server.
It is recommended that you use static IP addresses. An easy way to do this is to use your local DHCP and local DNS server (for many this will be their router).
Some examples of how to do that will be linked here in a little bit of time :)

1.1) How to find your hostname if you do not know it?
Open a terminal window and print
$ hostname  (without the $. It is for illustration purposes :)


1.2) If you think you need to change the hostname, this is how to do it

Open a terminal window
Become root 
$ su -

$ hostnamectl set-hostname "k8-master-1"    //this is an example hostname. Set whatever suit your needs

Add the following entries in /etc/hosts

$ nano /etc/hosts

your_ip_adress  k8-master-1
