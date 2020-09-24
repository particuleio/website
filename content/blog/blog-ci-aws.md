---
Title: Gérer son blog en serverless avec S3, CloudFront, Github et Travis
Date: 2016-12-08
Category: Amazon Web Services
Summary: Écrivez votre blog en Markdown et servez vous d'une CI pour générer le HTML et d'AWS pour le servir !
Author: Romain Guichard
image: images/thumbnails/amazon-s3.jpg
lang: fr
---

### Problématique

Depuis la fin de Skyblog (quoi ça existe encore ???), et l'avènement de CMS
comme Wordpress ou Joomla permettant à tout le monde de disposer d'un endroit où
raconter sa vie, donner son avis sur tout, etc., on a commencé à avoir accès
à des systèmes de blog plutôt facile à installer, à administrer et même parfois plutôt jolis.

Mais bon quand la volonté première est d'écrire du contenu, que la forme
importe peu et que surtout on n'a pas spécialement besoin de plugins ultra
stylés/kikoo, bah se connecter sur l'interface Wordpress pour écrire dans un
éditeur WYSIWYG, c'est pas fou. Ouais on aimerait bien pouvoir faire ça depuis
son terminal et dans une syntaxe simple, sans fioriture.

Première réponse : Markdown ou reStructuredText

__- Mais on choisit lequel ?__

Les deux se valent à mon avis, ici on parlera de Markdown pour la simple raison que
c'est ce qu'on a choisi sans trop y réfléchir. Tous les outils utilisés ici
supportent les deux langages donc ce n'est pas très important.
On peut donc commencer à écrire nos articles de blog de cette façon :

```
# Titre 1

Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor
incididunt ut **labore** et dolore magna aliqua. Ut enim ad minim veniam, quis
nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat.

![mon image](http://monsite.com/monimage.png)

## Titre 2

Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu
fugiat nulla pariatur. Excepteur [sint](http://sint.fr) occaecat cupidatat non proident,

- sunt in
- culpa qui officia
- deserunt mollit
- anim id est laborum
```

On se concentre sur le contenu, quelques "balises" à connaître par ci par là et
c'est fini.

### Le Markdown c'est un peu austère non ?

Alors oui, si on "convertissait" ça basiquement en HTML, ça serait pas top, on
n'a aucune notion de CSS avec le Markdown, aucun moyen de jouer avec les blocs, de
gérer les couleurs etc.

[Pelican](http://blog.getpelican.com/) est un exemple d'outil qui permet de
convertir du markdown vers de l'html. Hugo ou Ghost sont deux autres exemples
qui conviendraient très bien.

Donc Pelican, ça se compose basiquement d'un `pelicanconf.py` où vous allez retrouver
toute la configuration, d'un dossier _content/_ dans lequel vous allez placer vos fichiers
Markdown et d'un Makefile qui va lancer la conversion. Un dossier `output` sera
créé et vous pourrez récupérer les fichiers HTML.

Pour que Pelican fasse les choses bien, il a besoin de quelques tags dans votre
article. Ceux-ci vont définir la date, le titre, l'auteur etc.

```
Title: Lorem Ipsum
Date: 2016-11-03 14:00
Category: Amazon Web Services
Summary: Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do
Authors: Romain Guichard
Lang: fr
```

Chacun customise ça comme il le sent et on récupère des fichiers HTML en
sortie.
Pas mal de thèmes sont disponibles sur le [repository
Github](https://github.com/getpelican/pelican-themes).

Maintenant il nous faut un serveur web pour servir ces pages. Monter un Apache
juste pour servir des pages web statiques ? Ça va coûter cher en plus...

Pages = objets ? web = HTTP ?

Bonjour Amazon S3.

### Simple Storage Service

![Amazon S3](/images/amazons3.png)

Amazon S3 est un service d'object storage attaquable via une API HTTP. S3
fournit nativement un service de "website" permettant au travers d'une URL S3
`mon-bucket.s3-website-my_region.amazonaws.com` d'accéder à son site web.

On a donc juste à push tout notre dossier `output/` généré par Pelican dans un
bucket S3 et d'y activer le `Static Website Hosting`.

```
cd /blog
make html
cd output/
aws s3 mb s3://mon-bucket
aws s3 cp . s3://mon-bucket --recursive
aws s3 website s3://mon-bucket --index-document index.html
```

Il faut ensuite appliquer une policy à notre bucket

```
{
  "Version":"2012-10-17",
  "Statement":[
		{
		"Sid":"PublicReadGetObject",
    "Effect":"Allow",
	  "Principal": "*",
      "Action":["s3:GetObject"],
      "Resource":["arn:aws:s3:::mon-bucket/*"]
    }
  ]
}
```

Et voilà, notre site/blog est hosté.

Parlons argent maintenant. Outre le fait que S3 fait parti des services "free-tier",
son tarif est on ne peut plus abordable, à 3cts le Go + 0,4cts les 10 000 requêtes (images + pages), vous devriez vous en sortir ^^

Mais on peut faire mieux encore !

### CloudFront

![Amazon CloudFront](/images/amazon-cloudfront.png)

CloudFront est le service CDN d'AWS.

Un CDN (Content Delivery Network) est un réseau dont le but est de distribuer
du contenu (images, vidéos, pages web etc). Sa particularité est d'être composé
de PoP (Point of Presence) sur l'ensemble du globe. Ces PoP répliquent
l'information qu'ils recoivent entre eux, permettant ainsi de disposer de la
même information partout dans le monde. L'effet principal recherché est qu'un
internaute situé à Séoul, New York ou Paris recevra l'information du PoP le
plus près de chez lui.

Netflix est un très bon exemple de CDN.

CloudFront est un CDN dont font parties 43 villes (à l'heure où j'écris
ces lignes, ça change très souvent) dans le monde. Certaines comme
New York, Tokyo ou Londres possèdent même plusieurs PoP.

Nous ce qu'on aimerait c'est que CloudFront serve nos pages web situées sur S3.
Et c'est exactement ce qu'il sait faire !

On va commencer par créer une distribution Web. CloudFront peut aussi utiliser
RTMP pour servir du contenu multimédia mais ce n'est pas le but ici.

Ensuite c'est assez simple, il faut seulement faire attention à :

- __Nom du domaine d'origine__ qui va correspondre à votre bucket S3

Une fois validée, il faut attendre plusieurs minutes (une vingtaine
généralement) pour que notre distribution soit créée.

### CI avec Travis

![Travis CI](/images/travis_logo.png)

On a donc maintenant :

- Un langage simple pour écrire notre blog
- Un outil pour convertir ça en HTML
- Un service pour hoster nos pages
- Un CDN pour que n'importe qui dans le monde puisse voir notre blog dans de
  bonnes conditions

Tout ça manque quand même d'un peu d'automatisation.

__Travis__ est un service en mode SaaS de CI/CD. Il est très simple, il va pull
vos repo git à chaque commit et effectuer les actions spécifiées dans un
fichier .travis.yml situé à la racine de votre repo.

Voici le notre :

```
language: python
addons:
  apt:
    packages:
      - language-pack-fr
install:
  - pip install markdown pelican beautifulsoup4
script:
  - pelican --version
  - make html
branches:
  only:
    - master
deploy:
  - provider: s3
    skip_cleanup: true
    access_key_id: $MON_ACCESS_KEY
    secret_access_key: $MA_PRIVATE_KEY
    bucket: "blog.particule.fr"
    region: eu-west-1
    acl: public_read
    local_dir: output/
    on:
      branch: master
notifications:
  slack: $MA_SLACK_KEY
```

Très simple je disais donc. On installe les paquets nécessires, on lance notre
`make html`, on sait que le résultat va se retrouver dans un dossier `output/`,
on a donc plus qu'à envoyer tout ce dossier sur S3.

Malheureusement Travis ne gère pas le sync avec S3, il envoie donc à chaque
fois __tout__. Un peu long parfois...

On a ajouté une petite intégration avec Slack, comme ça on peut suivre
l'avancée des builds en même temps que d'envoyer des giphy de chats à ses
collègues.

Nous travaillons avec Travis, mais on peut surement faire la même chose avec
n'importe quelle CI, l'outil n'a vraiment pas d'importance ici.

Et voilà comment vous pouvez gérer votre blog. Nous n'avons absolument rien à manager,
tout est soit chez GitHub, chez AWS ou chez Travis.


**[Romain Guichard](https://linkedin.com/in/romainguichard)**
