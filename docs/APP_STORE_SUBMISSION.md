# GLPIKiosk - Preparation App Store

## Etat technique prepare dans le projet

- `Info.plist` visible dans Xcode via `fileGroups`
- `Media.xcassets` inclus comme ressource XcodeGen
- `PrivacyInfo.xcprivacy` ajoute au bundle
- `ITSAppUsesNonExemptEncryption = false` ajoute dans `Info.plist`
- lien de politique de confidentialite prevu dans l'app via la cle `PrivacyPolicyURL`
- `AccentColor.colorset` ajoute pour eviter une reference d'asset manquante
- fichiers parasites macOS a supprimer avant generation finale: `.DS_Store`, `._*`

## Actions obligatoires avant soumission

1. Renseigner une vraie URL de politique de confidentialite dans `GLPIKiosk/Info.plist` a la cle `PrivacyPolicyURL`.
2. Publier cette meme URL dans App Store Connect.
3. Regenerer le projet:

```bash
dot_clean -m .
find . -name '.DS_Store' -delete
find . -name '._*' -delete
xcodegen generate
```

4. Faire un build Release archive dans Xcode.
5. Verifier que `Info.plist`, `PrivacyInfo.xcprivacy` et `Media.xcassets` sont visibles dans Xcode.
6. Verifier que l'icone de l'app apparait bien sur simulateur/iPad.

## Reponses App Store Connect a preparer

### Export compliance

- Valeur preparee dans l'app: `ITSAppUsesNonExemptEncryption = false`
- A confirmer au moment de la soumission avec le responsable de publication si vous n'utilisez que le chiffrement standard Apple/HTTPS/Keychain/CryptoKit integre

### App Privacy

Le code montre que l'app peut transmettre au serveur GLPI:

- nom du signataire
- email du signataire
- signature manuscrite exportee en base64
- identifiant de l'appareil (`identifierForVendor` en fallback) ou numero de serie configure
- nom de l'appareil

Ces points doivent etre verifies puis reportes dans la fiche App Privacy App Store Connect.

### Notes de review

L'app depend d'un serveur GLPI externe et de credentials fonctionnels. Prevoir une note de review avec:

- URL de demonstration
- compte de test OAuth ou tokens legacy
- code admin si la review doit acceder aux reglages
- jeu de donnees de test permettant une demande de signature
- explication courte du mode kiosk

Modele recommande:

```text
GLPIKiosk est une borne iPad de signature pour GLPI.

Pour tester l'app:
1. Ouvrir l'app.
2. Utiliser la configuration deja prechargee.
3. Attendre une demande de signature ou utiliser la signature rapide.

Compte de test:
- URL:
- Login:
- Mot de passe:
- Code admin:

Notes:
- L'app communique avec un serveur GLPI de demonstration.
- La borne fonctionne en mode kiosk iPad.
```

## Points de vigilance avant envoi

### ATS

`NSAppTransportSecurity -> NSAllowsArbitraryLoads = true` est encore present.

Risque:

- Apple peut demander une justification en review.
- Si tous les serveurs cibles peuvent etre en HTTPS conforme ATS, il vaut mieux supprimer cette exception avant soumission.

### Politique de confidentialite

Apple demande un lien de politique de confidentialite dans App Store Connect et accessible dans l'app.

### Acces review

Sans serveur de demonstration et credentials de test, la review a un fort risque d'echec.

## Tests finaux recommandes

1. Installation propre sur iPad vierge
2. Setup complet
3. Checkin initial
4. Polling en attente
5. Veille noire puis reveil
6. Requete de signature recue
7. Signature et envoi
8. Signature rapide BL
9. Signature rapide Ticket
10. Mode hors ligne puis reprise reseau
11. Export des logs debug
12. Verification de l'icone, du nom app, de la version et du lien de confidentialite
