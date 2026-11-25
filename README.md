# Social Ride App

App Flutter + Firebase per ride di gruppo in bici:

- posizione live sulla mappa
- avviso automatico quando qualcuno si stacca dal gruppo
- audio personalizzato di allontanamento
- codice ride condivisibile

Target: gruppi piccoli (5–15 rider). Stack: Flutter, Firestore, Cloud Functions, FCM, Storage.

## Struttura

```
social_ride_app/     Flutter app (Android + iOS)
functions/           Cloud Functions (drop-off + TTL cleanup)
firestore.rules      Security rules
storage.rules
firestore.indexes.json
docs/                Design e plan
```

## Setup

### Prerequisiti

- Flutter SDK 3.x
- Node.js 20+ (per le functions)
- Firebase CLI (`npm i -g firebase-tools`)
- Progetto Firebase con: Auth (Anonymous), Firestore, Storage, FCM, Functions

### App Flutter

```bash
cd social_ride_app
flutter pub get
# Configura Firebase (genera lib/firebase_options.dart)
flutterfire configure --project=<your-project-id>
flutter run
```

Inserisci la Google Maps API key in:

- Android: `android/app/src/main/res/values/strings.xml` (`google_maps_key`)
- iOS: `ios/Runner/AppDelegate` / Info.plist come da plugin

### Cloud Functions

```bash
cd functions
npm install
npm test
firebase deploy --only functions
```

Function principali:

- `onRiderPositionWritten` — valuta drop-off e invia push
- `cleanupExpiredRides` — ogni 24h elimina ride `ended` più vecchie di 24h

### Rules e indici

```bash
firebase deploy --only firestore:rules,firestore:indexes,storage
```

## Test

```bash
# Functions (Node)
cd functions && npm test

# Flutter unit / widget
cd social_ride_app && flutter test
```

## Flusso utente

1. Auth anonima all’avvio
2. Crea ride (codice a 6 caratteri) o unisciti con il codice
3. La condivisione GPS parte in automatico
4. Mappa + alert se qualcuno supera soglia distanza per il dwell time
5. Il creatore termina la ride; dopo 24h i dati vengono cancellati

## Sicurezza (sintesi)

- Lettura posizioni / track / audio: solo membri della ride
- `get` sul documento ride: autenticati (serve per validare il codice)
- `list` rides: negato
- Solo il creator aggiorna soglie o chiude la ride

## Note Android

Con la condivisione attiva Geolocator avvia un **foreground service** con notifica persistente, così il tracking continua con lo schermo spento. Servono i permessi già dichiarati in `AndroidManifest.xml` (location background, FGS, notifiche).
