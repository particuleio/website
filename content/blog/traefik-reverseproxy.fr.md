---
lang: fr
Title: Traefik, un reverse-proxy pour vos conteneurs
Date: 2016-09-20
Category: Docker
Summary: Traefik est un reverse-proxy intelligent pour vos conteneurs supportant Docker, Kubernetes, Consul, etcd etc
Author: Romain Guichard
image: images/thumbnails/docker-generic.png
---

**[Update 04/2018]**

<center><img src="/images/traefik.logo.png" alt="traefik" width="400" align="middle"></center>

Un des problèmes rencontrés lorsque l'on travaille avec des conteneurs, c'est de pouvoir tracker leur cycle de vie afin d'y envoyer (ou non) le trafic qui lui est destiné. Dans le cas d'un service load-balancé, il est important que nos conteneurs s'enregistrent d'eux même pour passer proprement à l'échelle.

Les reverseproxy comme Nginx ou HAProxy ne gèrent pas nativement ce genre de comportement. Mais : Y'a Traefik ! Et Traefik est un reverse-proxy un peu plus récent et donc un peu plus intelligent que Nginx ;)

# On cherche à faire quoi déjà ?

La problématique est un peu toujours la même : un conteneurs ça apparait et disparait assez vite, on ne veut pas avoir à maitriser le port de l'host sur lequel ils écoutent. Et quand il s'agit de webservices, ça devient vite problématique...
Consul et les discovery services en général solutionnent une partie du problème, on a un outil qui permet de savoir ce qui tourne et où. C'est bien, mais si on pouvait exploiter ces infos ça serait mieux.

Dans le cas de webservices, on cherche à avoir un reverse-proxy qui sache en "temps réel" où se trouvent nos conteneurs et sache sur quel groupe de conteneurs forwarder les requêtes destinées à une URL donnée. Si on peut load-balancer entre plusieurs conteneurs et disposer de plusieurs backends, ça serait top.

<br />

# Traefik

Je présente ici Traefik. Traefik a été écrit par [Emile Vauge](https://github.com/EmileVauge), c'est français, bien de chez nous, donc c'est bien !

Traefik est donc un reverse-proxy et un load-balancer fait pour déployer principalement des microservices (ie conteneurs). Il est nativement simple puisque sa configuration propre est extrêmement limitée étant donné que celle-ci est majoritairement "déléguée" à ses backends. Et parmi ces backends, on compte Docker, Consul, k8s, mesos, etcd etc. Personne ne manque à l'appel. Traefik peut même être backé par de simples fichiers statiques et se comporter comme un reverse-proxy classique.

Pour notre première démonstration, on va utiliser directement le backend Docker.

Comme pour Registrator et Consul, il faudra donner à notre conteneur Traefik accès au socket Docker afin que celui ci puisse accéder aux évènements.

Utilisons docker-compose pour créer les conteneurs nécessaires :

```
version: '2'
services:
  traefik:
    image: traefik:1.5
    command: --web --docker --logLevel=DEBUG
    ports:
      - "80:80"
      - "8080:8080"
    volumes:
      - "/var/run/docker.sock:/var/run/docker.sock"
      - "$PWD/traefik.toml:/traefik.toml"

  webapp:
    image: particule/helloworld
    labels:
      - "traefik.port=80"
      - "traefik.backend=hello"
      - "traefik.frontend.rule=Host:hello.docker"
```

Rien de spécial du côté du conteneur Traefik. Une interface web est dispo sur le port 8080.

Pour notre webapp de test, j'ai repris l'image dockercloud/hello-world modifiée avec le logo particule, qui nous permettra de vérifier la load balancing simplement.
Les labels servent à donner les informations à Traefik.

  * Un backend représente ici un service. Si traefik décide de forwarder les requêtes web à un backend, celles-ci seront load balancées entre tous les conteneurs appartenant à ce backend.
  * Un frontend peut être assimiler à la directive `server_name` chez Nginx. Cela permet de contrôler le trafic entrant. Ici la règle est simple et stipule que le header http "Host" doit être à `hello.docker` pour faire parti de ce frontend.

D'autres labels peuvent être utilisés pour spécifier différents paramètres à Traefik comme le poids du conteneur au sein du backend.

Pas besoin d'exposer de port, nous sommes sur un seul host, le trafic se fera au sein du bridge docker0.

Ah et la conf Traefik `traefik.toml` !

```
[docker]
domain = "docker"
endpoint = "unix:///var/run/docker.sock"
watch = true
```

Ouais c'est tout.


On peut ensuite lancer tout ça : `docker-compose up -d`

Pour le test, j'ai ajouté `127.0.0.1 hello.docker` dans mon fichier `/etc/hosts`.

Vous pouvez tester l'URL `http://hello.docker` dans votre navigateur. La page du conteneur `particule/helloworld` devrait fonctionner.

Mais ce qui est vraiment intéressant c'est que si on augmente le nombre de conteneur `particule/helloworld`

```
docker-compose scale webapp=5
```

Et qu'on recharge plusieurs fois notre page web, on voit bien le round-robin s'effectuer !

## La même chose avec un discovery service existant

Dans l'exemple précédent nous avons donné accès à Traefik directement au socket Docker. Mais il est possible que votre infra dispose déjà d'un cluster Consul par exemple et que vous souhaitiez vous en servir comme backend pour Traefik.

Avec Consul, on a deux options, soit utiliser son KV Store ou son catalogue. De base, le KV Store est vide. Registrator ne peuple pas le KV Store mais le catalogue, le KV Store est juste là si vous en avez besoin mais il est vide de base.

Le catalogue :
```
curl localhost:8500/v1/catalog/services | jq .
{
  "consul": [],
  "hello": [],
  "particule/helloworld": [
    "traefik.backend=hello2",
    "traefik.frontend.rule=Host:hello2.particule.io"
  ]
}
```
Le KV Store
```
curl http://localhost:8500/v1/kv/\?recurse

curl -X PUT -d 'good' http://localhost:8500/v1/kv/web/particule
curl  http://localhost:8500/v1/kv/\?recurse | jq .
[
  {
    "CreateIndex": 35,
    "ModifyIndex": 35,
    "LockIndex": 0,
    "Key": "web/particule",
    "Flags": 0,
    "Value": "Z29vZA=="
  }
]
```

Le KV doit être rempli pour être utilisé. Il y'a donc peu de chance que vous ayez privilégié cette méthode alors que des outils comme registrator peuvent faire le travail pour vous et peupler le catalogue.


Repartons sur un docker-compose.yml :

```
version: "2"
services:
  consul:
    image: progrium/consul
    command: -server -bootstrap
    ports:
      - "8500:8500"
    labels:
      SERVICE_IGNORE: "true"

  registrator:
    depends_on:
      - consul
    image: gliderlabs/registrator
    command: -internal consul://172.17.0.1:8500
    volumes:
      - "/var/run/docker.sock:/tmp/docker.sock"

  traefik:
    depends_on:
      - consul
    image: traefik:1.5
    ports:
      - "80:80"
      - "8080:8080"
    volumes:
      - "$PWD/traefik.toml:/traefik.toml"
    labels:
      SERVICE_IGNORE: "true"

  hello:
    image: particule/helloworld
    labels:
      SERVICE_NAME: "hello"
  hello2:
    image: particule/helloworld
    labels:
      SERVICE_TAGS: "traefik.backend=hello2,traefik.frontend.rule=Host:hello2.particule.io"
```

Et le traefik.toml

```
logLevel = "DEBUG"

[web]
address = ":8080"

[consulCatalog]
endpoint = "172.17.0.1:8500"
domain = "consul.local"
prefix = "traefik"
```

Prenons le conteneur "hello" :
Si aucun SERVICE_NAME n'est défini, une URL de la forme "nom_image"."traefik_domain" sera créee.
SERVICE_NAME permet d'override le nom de l'image et vous pouvez override toute l'URL avec `traefil.frontend.rule`.
Les paramètres Traefik ne sont plus passés directement au conteneur mais sont passés à Consul via SERVICE_TAGS :
```
curl localhost:8500/v1/catalog/service/helloworld | jq .
[
  {
    "Node": "128688b27e1f",
    "Address": "172.18.0.3",
    "ServiceID": "0a2be7713001:consul_hello2_1:80",
    "ServiceName": "helloworld",
    "ServiceTags": [
      "traefik.backend=hello2",
      "traefik.frontend.rule=Host:hello2.particule.io"
    ],
    "ServiceAddress": "172.18.0.4",
    "ServicePort": 80
  }
]
```


Deux URL sont donc disponibles, `hello.consul.local` et `hello2.particule.io` donnant respectivement accès aux backends `hello` et `hello2`.


# Conclusion

Bien que consul-template permettait déjà d'effectuer beaucoup d'update de configuration de façon automatique, Traefik apporte énormément de simplicité et de puissance ainsi qu'une compatibilité avec énormément de produit.

Une présentation des [Ingress Controllers sous Kubernetes ainsi qu'une intérgration avec Traefik et Let's Encrypt est disponible](https://dev.particule.io/blog/kubernetes-ingress/) !


**[Romain Guichard](https://www.linkedin.com/in/romainguichard)**
