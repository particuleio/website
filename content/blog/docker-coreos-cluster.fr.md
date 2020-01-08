---
Title: CoreOS, cluster et Docker
Date: 2016-01-06T10:00:00+00:00
Category: Docker
Summary: CoreOS est une distribution linux minimaliste complètement orientée vers Docker. Elle permet grâce à des outils natifs de monter des clusters pour containers Docker.
Author: Romain Guichard
image: images/thumbnails/docker-generic.png
lang: fr
---

<center><img src="/images/docker/coreos.png" alt="coreos" width="400" align="middle"></center>

CoreOS est une distribution Linux minimaliste. Son but est de permettre le déploiement
massif de services en intégrant nativement des outils comme fleet pour la gestion
des clusters et Docker pour la gestion des applications.

CoreOS est une distribution orientée cloud, elle ne fonctionne pas sans Internet
car ses mises à jour sont poussées directement dans le système sans action utilisateur.
Créer ou rejoindre un cluster avec etcd nécessite aussi un accès Internet.
CoreOS se distingue aussi par le fait qu’il ne dispose pas de gestionnaire de paquets,
en fait vous ne pouvez rien installer. Toute application doit passer par un container Docker dans lequel vous êtes libre
de faire ce dont vous avez besoin.

Sur le principe, si vous voulez avoir mtr (mytraceroute) il faut faire ceci :

```
Dockerfile:
-----
FROM alpine:3.2
RUN apk -U add mtr
ENTRYPOINT mtr
-----
docker build -t mtr .
alias mtr='docker run -it --rm=true mtr'
```
Ensuite vous pouvez utiliser mtr comme s'il s'agissait d'un programme normal.

Autre point notable de CoreOS, il existe trois channels, alpha, beta et stable.
Alpha la version la plus avancée, reçoit plus de maj que beta, qui elle en
reçoit plus que stable. Une mise à jour sur CoreOS se fait par
un reboot et celui ci est, par défaut, automatique, CoreOS allant lui
même chercher ses updates et se les appliquant comme un grand. Dans le cas où
vous souhaitez utiliser une version alpha, attendez à vous à au moins un reboot
par semaine. En fonction du channel utilisé, il vaut mieux prévoir un cluster
pour anticiper ces reboots.

A noter qu'il est possible de passer de stable à beta et de beta à alpha, mais
le downgrade n'est en revanche pas possible.

Voilà pour l’introduction de CoreOS.

Comme la plupart des OS modernes, CoreOS offre la possibilités d’être configuré au
boot par l’intermédiaire d’un fichier cloud-config. Ce fichier au format YAML
permet de définir les paramètres de notre système (IP, unit, clé ssh etc).

Malheureusement les produits VMware ne permettent pas de passer un fichier cloud-config
à une vm. Il faut pour cela le passer via un fichier ISO monté dans le lecteur virtuel.
La procédure pour VMware se trouve [ici ](http://www.chrismoos.com/2014/05/28/coreos-with-cloud-config-on-vmware-esxi). Si vous pouvez avoir un vrai cloud provider sous la main c'est mieux...

Ne reprenez pas le cloud-config du tuto, nous allons en générer un nouveau.

### Etcd

<center><img src="/images/docker/etcd.png" alt="etcd" width="250" align="middle"></center>

Le premier élément du système de cluster de CoreOS est etcd. Etcd est un système
de clé/valeur distribué. Il prend en charge la gestion des noeuds dans le cluster.
Etcd est installé sur tous les noeuds d’un cluster et son système distribué
lui permet d’être requêté par n’importe quel container du cluster.

### Fleet

Fleet est l’orchestrateur du cluster. Il place les containers, gère les dépendances
et les conflits entre les containers. Son rôle est de gérer systemd mais au niveau du cluster.

### Mise en cluster

Pour créer un cluster il nous faut récupérer une clé pour la découverte des noeuds :

`curl -w "\n" 'https://discovery.etcd.io/new?size=X'`

Avec X le nombre de noeuds initialement présents dans le cluster. On récupère une URL du type https://discovery.etcd.io/3135e6ea19cf3135e6ea19cf.

Pour nous connecter à nos noeuds, une clé ssh serait la bienvenue :

`ssh-keygen -b 2048 -f ~/coreosPrivateKey.key`

On peut commencer à rédiger notre fichier cloud-config.

Tout d’abord un fichier cloud-config commence toujours par #cloud-config et viennent ensuite différentes sections, chacune configurant une partie du système :

```
#cloud-config
    ssh_authorized_keys:
        - ssh-rsa VOTRE_CLE_PUBLIQUE core@coreos
    coreos:
        etcd:
            discovery: VOTRE_URL
            addr: $private_ip:4001
            peer-addr: $private_ip:7001
            peer-election-timeout: 3000
            peer-heartbeat-interval: 600
    units:
        - name: etcd.service
            command: start
        - name: fleet.service
            command: start
```

Les variables $private_ip sont interprétées par certains systèmes (à ma
connaissance tous sauf VMWare ^^) et seront remplacés par votre IP réelle. Cela
permet de ne pas se soucier de l'IP fournie par le DHCP et d'avoir un
cloud-config unique pour tous les hosts de votre cluster.

En revanche si vous utilisez VMware, on est obligé de s’adapter. Il faut désactiver
le dhcp dans votre unit-file et fixer une IP à votre interface réseau. Il faudra
ensuite annoncer cette IP dans la partie etcd.
C'est manipulation devra être répétée et adaptée pour tous les noeuds du
cluster.

Une fois démarré, vous devriez pouvoir accéder à un de vos noeuds en ssh.

Si il s’agit du premier noeud à démarrer, la commande « systemctl status etcd -l » devrait vous montrer son élection en tant que master :

```
Mar 27 15:29:40 coreos-node1 etcd[8759]: [etcd] Mar 27 15:29:40.811 INFO      | ccc095d945964a97d95b2f0377a41e: state changed from 'follower' to 'candidate'. Mar 27 15:29:40 coreos-node1 etcd[8759]: [etcd] Mar 27 15:29:40.811 INFO      | ccc095d945964a97d95b2f0377a41e: state changed from 'candidate' to 'leader'. Mar 27 15:29:40 coreos-node1 etcd[8759]: [etcd] Mar 27 15:29:40.811 INFO      | ccc095d945964a97d95b2f0377a41e: leader changed from '' to 'ccc095d945964a97d95b2f0377a41e'.
```

Et sur le second noeud :

```
Mar 27 15:30:29 coreos-node2 etcd[9523]: [etcd]
Mar 27 15:30:29.001 INFO      | Send Join Request to http://10.0.0.100:7001/join
Mar 27 15:30:29 coreos-node2 etcd[9523]: [etcd]
Mar 27 15:30:29.026 INFO      | ac2619b7463c4f41bfccd7b49a6aa8 joined the cluster via peer 10.0.0.100:7001
Mar 27 15:30:29 coreos-node2 etcd[9523]: [etcd] Mar 27 15:30:29.028 INFO      | etcd server [name ac2619b7463c4f41bfccd7b49a6aa8, listen on :4001, advertised url http://10.0.0.101:4001]
Mar 27 15:30:29 coreos-node2 etcd[9523]: [etcd] Mar 27 15:30:29.028 INFO      | peer server [name ac2619b7463c4f41bfccd7b49a6aa8, listen on :7001, advertised url http://10.0.0.101:7001]
Mar 27 15:30:29 coreos-node2 etcd[9523]: [etcd] Mar 27 15:30:29.028 INFO      | ac2619b7463c4f41bfccd7b49a6aa8 starting in peer mode
Mar 27 15:30:29 coreos-node2 etcd[9523]: [etcd] Mar 27 15:30:29.029 INFO      | ac2619b7463c4f41bfccd7b49a6aa8: state changed from 'initialized' to 'follower'.
Mar 27 15:30:29 coreos-node2 etcd[9523]: [etcd] Mar 27 15:30:29.610 INFO      | ac2619b7463c4f41bfccd7b49a6aa8: state changed from 'follower' to 'snapshotting'.
Mar 27 15:30:29 coreos-node2 etcd[9523]: [etcd] Mar 27 15:30:29.648 INFO      | ac2619b7463c4f41bfccd7b49a6aa8: peer added: 'ccc095d945964a97d95b2f0377a41e'
```

Et sur n’importe quel noeud, on peut voir la liste des machines dans le cluster :

```
$ fleetctl list-machines
MACHINE         IP              METADATA
ac2619b7...     10.0.0.101     -
ccc095d9...     10.0.0.100     -
```

Maintenant que notre cluster est up and running, on va pouvoir créer nos units (= nos applications) et les pousser sur le cluster.

On va commencer par un serveur web nginx et on va utiliser l’image nginx du repository
Osones (osones/nginx). Nginx est un serveur de web et il est extrêmement courant
d’avoir plusieurs frontaux web, il faut donc prévoir notre fichier d’unit comme
un template qui permettra de créer plusieurs instances de notre Nginx.

Un unit file ressemble à ceci :

```
core@coreos-node1 /etc/systemd/system $ cat nginx@.service
[Unit]
Description=Nginx-frontend
After=docker.service
Requires=docker.service

[Service]
TimeoutStartSec=0
ExecStartPre=-/usr/bin/docker kill nginx
ExecStartPre=-/usr/bin/docker rm nginx
ExecStartPre=/usr/bin/docker pull osones/nginx
ExecStart=/usr/bin/docker run -rm --name nginx -p 80:80 osones/nginx
ExecStop=/usr/bin/docker stop nginx

[X-Fleet]
Conflicts=nginx@*.service
```

Noter bien que par rapport à une commande docker run « classique », le paramètre « -d »
n’apparait pas. En effet, en mode détaché, le container n’est pas lancé comme un
enfant du processus de l’unit et se coupe après quelques secondes d’exécution.

On submit ensuite l’unit à fleet et on la lance :

```
fleetctl submit nginx@.service
fleetctl start nginx@1
fleetctl start nginx@2
fleetctl list-units
UNIT                    MACHINE                 ACTIVE  SUB
nginx@1.service        ccc095d9.../10.0.0.100 active  running
nginx@2.service        ac2619b7.../10.0.0.101 active  running

```

Nos deux containers ont bien été lancés sur deux noeuds différent grâce à la
directive « conflicts ». Cette directive permet aussi de lier des containers et
de toujours les laisser sur le même host ou bien de lancer un container sur
un host qui respecte certaines metadata (lieu géographiques, type de plateforme etc)
fournies dans un cloud-config.

La section X-Fleet de notre unit file accepte plusieurs paramètres pour le placement de nos containers :

- MachineID <host> : Sur l’host identifié par son nom
- MachineOf <unit> : Sur l’host faisant tourner <unit>
- MachineMetadata : Sur le/les host(s) matchant les metadata spécifiées
- Conflicts <unit> : Élimine les hosts faisant tourner <unit>
- Global=true : Fait tourner le container sur tous les hosts du cluster


Cette présentation plutôt rapide de CoreOS et de ses fonctionnalités de cluster
intégrées permettent de monter des applications résilientes relativement
simplement.

**Romain Guichard**

### - Encore un peu de temps ? Nous avons pleins d'autres articles sur Docker :

<center>
### [Discovery Service avec Consul](http://blog.osones.com/discovery-service-avec-consul.html)
<img src="/images/docker/consul.png" alt="consul" width="200" align="middle"></center>
<br>

<center>
###  [Container as a Service avec Amazon EC2 Container Service (ECS)](http://blog.osones.com/container-as-a-service-avec-amazon-ec2-container-service-ecs.html)
<img src="/images/ECS/AmazonEC2ContainerService_Banner.png" alt="Amazon ECS" width="500" align="middle"></center>
<br>
