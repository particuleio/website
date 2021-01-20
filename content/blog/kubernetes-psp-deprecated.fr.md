---
Title: Kubernetes va déprécier les PodSecurityPolicy
Date: 2021-01-20
Category: Kubernetes
Summary: "Kubernetes va déprécier, à partir de la `1.21`, les PSP, ces
composants permettant d'assurer la sécurité au niveau du pod. Pourquoi ? Quelles
alternatives ?"
Author: Romain Guichard
image: images/thumbnails/kubernetes.png
imgSocialNetwork: images/og/kubernetes-psp-deprecated.png
lang: fr
---

Après l'annonce il y a quelques semaines de [la fin du support de Docker au
sein de Kubernetes](https://particule.io/blog/kubernetes-docker-support/),
c'est au tour des PodSecurityPolicy (PSP) de subir le même sort.

Suite à [la PullRequest
\#97171](https://github.com/kubernetes/kubernetes/pull/97171), les
PodSecurityPolicy seront dépréciées à partir de la version `1.21` puis
supprimées lors de la version `1.26`. Ce qui situe leur suppression dans 6
releases, soit approximativement 18 mois au rythme actuel des releases.

Nous vous avions déjà parlé des PSP dans [un précédent
article](https://particule.io/blog/kubernetes-psp/). Ces ressources permettent
d'enforcer certaines règles au niveau du pod, on peut citer par exemple :

- impossibilité d'effectuer une élévation de privilèges (sudo)
- impossibilité de démarrer en root
- impossibilité d'utiliser des volumes hostPath
- impossibilité de créer un pod "privileged"
- etc

Les PSP étaient activées au moyen d'un AdmissionControler au sein de l'API et
les PSP elles mêmes devaient être utilisées par les utilisateurs créant le pod
(ou le ServiceAccount) pour être prises en compte.

Ce qu'on se rend tout de suite compte c'est que leur utilité n'est pas
surcotée, les PSP sont des briques essentielles pour assurer une protection
entre un pod et son host.

![psp](https://rancher.com/img/blog/2020/pod-security/picture2.png)
*© crédits Rancher*

## Mais pourquoi les déprécier alors ?

Il y a plusieurs raisons qui ont poussé la communauté à faire ce choix.

Tout d'abord, où en sont les PSP aujourd'hui ? Et bien elles sont en beta.
Depuis la version `1.8`. Cela fait donc 3 ans qu'elles n'ont pas bougé. En
"temps Kubernetes" c'est énorme et cela peut démontrer (et c'est le cas ici)
une incapacité de la communauté à les faire évoluer simplement et proprement.

Les PSP sont des composants optionnelles non activées par défaut, c'est donc à
l'administrateur de les activer, de créer les règles puis de les associer. Nous
faisions d'ailleurs remarquer dans notre article qu'activer les PSP "juste pour
voir" finissait souvent en drâme avec un cluster cassé. En effet, à leur
activiation, aucune règle n'est probablement disponible et l'apiserver refusera
donc tous les pods soumis. Tous. Un peu touchy à mettre en place donc. On ne
peut pas vraiment considérer cela comme une sécurité par défaut.

Le système de RBAC des PSP est lui aussi remis en cause. Ce qu'il faut
comprendre c'est qu'un administrateur n'oblige pas un namespace d'utiliser
telle ou telle PSP (même si c'est possible en bidouillant). Un administrateur
met des PSP à disposition et il doit ensuite associer ces PSP à des
utilisateurs ou à des ServiceAccount. Et pour ça l'utilisateur ou le
ServiceAccount doivent avoir le droit `use` sur la PSP correspondante. Pas très
intuitif.

On peut ajouter à ces problèmes l'absence de finesse dans l'attribution des
PSP, la confusion dans la priorité entre les PSP mutating et non-mutating etc.

## Quelles solutions ?

La première idée est de travailler sur une PodSecurityPolicy v2 en corrigeant
les problèmes cités plus haut.

La seconde est d'implémenter un mécanisme built-in et par défaut dans
Kubernetes avec le strict minimum pour faire fonctionner un équivalent des PSP.
Cela impliquerait d'hardcoder une règle "allow-all" par défaut et manquerait de
customisations pour les utilisateurs avancés.

La dernière solution consiste à sortir la fonctionnalité de Kubernetes et
la déléguer à des solutions tiers. Cela aurait pour avantage d'être
totalement souple dans le développement des solutions tiers puisqu'elle se
baserait sur le principe des admission webhook et leur capacité quasi
illimitée. A l'inverse, cela veut dire dire adieu à une fonctionnalité
out-of-the-box et donc un cluster pas (totalement) sécurisé par défaut. Des
solutions tiers, bien qu'encourageant la diversité et la concurrence, risquent
de morceller l'écosystème. Une alternative à cette solution serait de définir
une norme afin d'éviter la fragmentation, peut être une future **Container Policy
Interface** ?

## La relève existe déjà !

Ça sentait le sapin pour les PodSecurityPolicy depuis quelques temps. Et
d'autres solutions existent déjà :

- **[OpenPolicyAgent](https://github.com/open-policy-agent/opa)** avec
  [Gatekeeper](https://github.com/open-policy-agent/gatekeeper)
- [Kyverno](https://kyverno.io/)

Ces deux projets sont tous les deux incubés par la Cloud Native Computing
Foundation.

La relève est donc assurée.

**[Romain Guichard](https://fr.linkedin.com/in/romainguichard/)**
