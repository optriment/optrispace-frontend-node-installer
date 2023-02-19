# OptriSpace Frontend Node Installer

This repository includes everything to set up and configure your
own OptriSpace frontend node.

## Requirements

### Server

The minimal server requirements to run OptriSpace frontend are:

- Operating System: Debian 10 (ONLY!)
- CPU: 2+
- RAM: 2+ GB
- Disk Space: 30+ GB
- One external IP Address

### Other information

- Your frontend node key (ask OptriSpace Team)
- Registered domain name
- DNS A-record for your domain must be set to your server IP address
- Your `root`'s user password (check your hosting panel or your email)

## What will be installed on your server

We would like to let you know about scripts, applications, and files\
which will be installed to your own server using our installation script.

### Third party packages and applications

- [nginx](https://www.nginx.com/)
- [Docker](https://www.docker.com/)
- [acme.sh](https://github.com/acmesh-official/acme.sh)

### OptriSpace projects

- [OptriSpace Frontend](https://github.com/optriment/optrispace-frontend-v2)
- [Installation script](https://github.com/optriment/optrispace-frontend-node-installer/blob/master/install.sh)
- [nginx config](https://github.com/optriment/optrispace-frontend-node-installer/blob/master/assets/nginx_domain.conf)

### Additionally

- User `deploy` will be added on the server (without password) to run application
- SSL certificate will be issued for your domain name
- acme.sh script will be added to root's crontab for renewing SSL certificate

## Connect to your server

Open Terminal app in your operating system and run the following command:

```sh
ssh root@YOUR_SERVER_IP
```

Confirm the connection request (type `yes`):

```plain
The authenticity of host can't be established.
Are you sure you want to continue connecting (yes/no/[fingerprint])?
```

Server will ask you for your `root` user password:

```sh
root@YOUR_SERVER_IP password:
```

You will see the server prompt:

```text
root@vbyobukitv:~#
```

**Please execute all following commands being connected to your server by SSH!**

## Download installation script

Download script into your server:

```sh
curl -o install.sh https://raw.githubusercontent.com/optriment/optrispace-frontend-node-installer/master/install.sh
```

Set executable bit for this script:

```sh
chmod +x ./script.sh
```

## Configure server

**IF YOU MAKE A MISTAKE IN YOUR DOMAIN NAME OR FRONTEND NODE KEY,\
SERVER WILL BE IN A WRONG STATE! PLEASE PAY ATTENTION TWICE!**

Installation script expects 2 arguments: domain name and frontend node key.

Let's imagine you have the following values:

- Domain name: `domain.tld`
- Frontend node key: `0x12345678` (must have `0x` in the beginning!)

Paste the following command into your terminal (do not forget to use real values!):

```sh
./install.sh domain.tld 0x12345678
```

Now you need to wait for 15-20 minutes for the installation script to install all
the requirements.

## What is next?

When you find the following message in your terminal, then you have installed
and fully configured frontend node!

```plain
[INFO] Restarting nginx...
```

Open your domain name in your web browser.

## Troubleshooting

If you have any questions, feel free to contract us on
[Discord](https://discord.gg/7WEbtmuqtv) or via
[GitHub issues](https://github.com/optriment/optrispace-frontend-node-installer/issues/new).
