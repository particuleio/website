---
lang: fr
Title: Discovery Service avec Consul
Date: 2015-12-14T11:00:00+00:00
Category: Docker
Summary: Un discovery service pour conteneurs avec Consul
Author: Romain GUICHARD
image: images/thumbnails/docker-generic.png
---


<center><img src="/images/docker/consul.png" alt="consul" width="200" align="middle"></center>

Afin de gérer de multiples conteneurs Docker, il est important d'avoir une vision
précise de ce qui tourne sur votre infrastructure. Avec des systèmes legacy,
les changements sont peu nombreux au cours du temps, tout est relativement
fixe. Les VM vont elles bouger plus ou moins régulièrement entre vos hosts, les
instances de par leur caractère éphémère sont promptes à apparaître et
disparaitre en fonction de l'autoscalabilité de votre cloud.

Les conteneurs se comportent comme les instances, mais encore plus rapidement.
Si vos applicatifs sont gérés correctement, ils risquent d'être gérés par une
multitude de conteneurs, une application web aura un/des conteneur(s) pour
Apache, PHP, MySQL par exemple. Outre les aspects de supervision qui peuvent
entrer en compte, il est important que ces conteneurs connaissent leur voisins,
sachent où ils sont, sur quelles IP les contacter et via quel port. Ces
informations peuvent être obtenues via un service de discovery.

Je présenterai ici Consul, un produit libre d'HashiCorp qui développe
notamment Vagrant, Packer ou bien encore Terraform.

### Ce que Consul change

<center><img src="/images/docker/hashicorp.png" alt="hashicorp" width="500" align="middle"></center>

La première réponse qui peut venir à l'esprit pour connecter des conteneurs
ensemble ce sont les links. En effet si vous linkez votre conteneur Nginx à
conteneur MySQL, Nginx pourra communiquer avec MySQL au travers du nom choisi
grâce au fichier */etc/hosts* rempli par Docker.

OK ça marche. Maintenant imaginons que vous avez un frontal web connecté à son
backend avec un link. Que se passe t-il si le conteneur contenant votre backend
tombe puis remonte ? Le link est cassé car celui ci est statique. Moche.

Ce que Consul propose, c'est une API HTTP et DNS permettant à tous instants à
vos conteneurs de connaître l'état de votre infra.

- Qui tourne ?
- Où ?
- Sur quelle IP ? Quel port ? TCP, UDP, les deux ?
- Quel est son nom ?

Consul utilise un magasin Key/Value (KV store) pour stocker l'état de vos
conteneurs. Ce KV store est attaquable à coup de Curl et renvoie du JSON. Le KV
Store utilisé par Consul ressemble en tous points à des produits comme
Zookeeper ou Etcd. Consul nécessite comme ces derniers un quorum pour
fonctionner. En revanche, contrairement à Etcd et Zookeeper qui ne fournissent
qu'un KV store, les données qui y sont stockées sont brutes, Consul lui est fait
pour du discovery et les données seront déjà "rangées" proprement, vous
permettant un accès rapide à l'information nécessaire. Consul intègre des
mécanismes avancés de health check quand d'autres systèmes vont simplement
utiliser un heartbeat pour vérifier la disponibilité d'un service.

SkyDNS est en revanche un concurrent plus "direct" à Consul. Leur
fonctionnement est très proche, la différence se fait notamment encore une fois
sur le système de health check moins poussé chez SkyDNS qui ne se contente que
d'un heartbeat et de TTL.

Il est important de faire remarquer que Consul fourni une interface pour la
découverte des services, il ne découvre en revanche pas lui même les services
sur votre infra. Une brique supplémentaire est nécessaire pour ceci. Nous
utiliserons l'image registrator de gliderlabs pour cette action. Registrator va
écouter le daemon Docker et enregistrer les informations dans le KV store de
Consul.


### Mise en place du cluster Consul

Pour une simple question d'efficacité, je ferai tourner un seul noeud Consul. Les
bonnes pratiques voudraient que Consul soit composé d'un cluster d'au moins
trois noeuds (pour avoir un quorum) mais cela n'est pas nécessaire pour
présenter son fonctionnement en tant que service de discovery.

Nous avons donc besoin de 2 conteneurs, 1 consul et 1 registrator, commençons
par Consul.

Par défaut Consul annonce pour chaque conteneur présent sur le même host que lui
l'IP de l'host en question. Cela ne pose en soit pas de problème mais vous oblige à mapper les ports de vos
conteneurs sur votre host pour que ceux ci soient accessibles. Dans le cas d'une
infra mononode, cela est inutile puisque le trafic restera interne. Le fait
d'utiliser l'IP locale des conteneurs est une information qu'il faudra passer
en paramètre à Registrator.

```bash
docker run -d -h consul -e "SERVICE_NAME=consul" -p 8400:8400 -p 8500:8500 -p 8600:53/udp gliderlabs/consul-server -server -bootstrap
```
Les variables d'env permettent de nommer vos services. On verra ça quand on
lancera un service.

Consul prend -server ou -agent en paramètre en fonction du rôle donné.
Le rôle de server implique automatiquement le rôle d'agent.

```bash
docker run -d -v /var/run/docker.sock:/tmp/docker.sock gliderlabs/registrator -internal consul://172.17.0.1:8500
```

Noter que 172.17.0.1 est l'IP du bridge docker0 par défaut.

Le conteneur registrator reçoit juste en volume le socket docker pour écouter
les évènements et les enregistre sur Consul. Le `-internal` sert à préciser
d'enregistrer l'IP du conteneur plutôt que celle de son host.

Dans le cas d'une archi multihosts et à moins d'utiliser des réseaux overlay, il faudrait bien évidemment enlever ce
dernier paramètre. Les conteneurs doivent à ce moment être mappés sur votre
host de façon à être accessible de l'extérieur.

Dans le cas d'une archi multihosts, il faudrait positionner un conteneur
Registrator sur chaque host.


### Utiliser l'API

On va maintenant lancer deux conteneurs nginx pour vérifier le
fonctionnement.

```bash
docker run -d -e "SERVICE_NAME=nginx" vsense/nginx
docker run -d -e "SERVICE_NAME=nginx" vsense/nginx
```

```bash
$ curl localhost:8500/v1/catalog/services | jq .
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed
100   181  100   181    0     0   104k      0 --:--:-- --:--:-- --:--:--  176k
{
  "consul": [],
  "consul-53": [
    "udp"
  ],
  "consul-8300": [],
  "consul-8301": [
    "udp"
  ],
  "consul-8302": [
    "udp"
  ],
  "consul-8400": [],
  "consul-8500": [],
  "consul-8600": [
    "udp"
  ],
  "nginx-443": [],
  "nginx-80": []
}
```

*`jq` est un programme permettant de parser "simplement" du json, ici je ne m'en sers que pour avoir un affichage humainement lisible*

On voit tous les ports Consul (ceux exposés et non exposés) et on voit bien les deux ports de Nginx. Malgré le fait que nous ayons lancé deux fois le conteneur Nginx, nous avons utilisé le même nom
de service dans les deux cas, Consul ne voit donc qu'un seul service.

En détails cela donne ça :

```bash
$ curl localhost:8500/v1/catalog/service/nginx-80 | jq .
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed
100   361  100   361    0     0  31736      0 --:--:-- --:--:-- --:--:-- 32818
[
  {
    "Node": "consul",
    "Address": "172.17.0.2",
    "ServiceID": "ba3bd70cfdf4:sad_turing:80",
    "ServiceName": "nginx3-80",
    "ServiceTags": null,
    "ServiceAddress": "172.17.0.6",
    "ServicePort": 80
  },
  {
    "Node": "consul",
    "Address": "172.17.0.2",
    "ServiceID": "ba3bd70cfdf4:backstabbing_goldstine:80",
    "ServiceName": "nginx3-80",
    "ServiceTags": null,
    "ServiceAddress": "172.17.0.7",
    "ServicePort": 80
  }
]
```

On voit ici que les deux conteneurs tournent sur deux IP bien distinctes (.6 et .7).

Et avec DNS ?

```bash
$ dig @172.17.0.2 -p 8600 nginx3-80.service.consul +short
172.17.0.6
172.17.0.7
```

On voit bien que deux IP répondent au service "nginx-80"
Le nom de domaine est généré automatiquement par Consul. Le tld **.consul** peut être modifié dans la configuration de Consul. Nous avons utilisé une configuration par défaut, mais vous pouvez monter votre propre conf au démarrage du conteneur.

Il est possible de spécifier un nom pour votre service avec SERVICE_NAME mais
aussi un nom pour un port particulier avec SERVICE_numPORT_TAGS.

Cela peut donner quelque chose comme ça :

```bash
$ docker run -d -e "SERVICE_NAME=webserver" -e "SERVICE_80_TAGS=http" -e "SERVICE_443_TAGS=https" vsense/nginx
```

Un enregistrement DNS de ce type sera créé :

```bash
$ dig @172.17.0.2 -p 8600 http.webserver-80.service.consul +short
172.17.0.5
$ dig @172.17.0.2 -p 8600 https.webserver-443.service.consul +short
172.17.0.5
```

### Utiliser le service de discovery pour un service de load-balancing

Maintenant que l'on sait comment interroger notre service de discovery, on va
voir comment l'utiliser dans le cadre d'un load-balancer.

<center><img src="/images/docker/consul-template.png" alt="consul-template" width="500" align="middle"></center>

Consul fournit un utilitaire appelé [consul-template](https://github.com/hashicorp/consul-template).
Il permet de parser des templates et de remplacer des variables par des valeurs obtenues via Consul. Il
est ainsi possible de spécifier une liste de conteneurs à load-balancer en
fonction de leur état (conteneur UP et health check OK).

On va faire ça simplement avec nginx (ça marche avec n'importe quel service qui
utilise une conf texte). Voici le template :

```bash
upstream webserver {
  least_conn;
  {{range service "nginx-80"}}server {{.Address}}:{{.Port}} max_fails=3 fail_timeout=60 weight=1;
  {{else}}server 127.0.0.1:65535; # force a 502{{end}}
}

server {
  listen 80;
  server_name www.mastartup.io;

  location / {
    proxy_pass http://webserver;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
  }
}
```

Consul-template a un paramètre -dry permettant de tester le résultat du
template une fois parsé :

```bash
$ ./consul-template -consul $IP_CONSUL:8500 -template nginx.template -dry
```

Vous devriez obtenir les 2 IP de vos 2 conteneurs Nginx.

Le paramètre -template a la forme suivante : `-template template:fichier_destination:cmd_à_exécuter`

La commande à exécuter va vous servir notamment à reload Nginx lorsque le
fichier généré change.


### Conclusion

Cet article donne une base relativement succincte du fonctionnement de Consul,
il ne s'agit pas encore d'un vrai cluster et il sera intéressant de voir plus
tard ce que cela change.

Néanmoins, ce que nous avons actuellement est suffisant pour gérer ses services
et utiliser le KV store de Consul pour automatiser un peu tout ce
qu'on peut imaginer.


Enjoy ~.°


**Romain GUICHARD**
